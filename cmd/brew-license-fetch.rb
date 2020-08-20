require "licensee"
require "net/http"

def license_fetch_args
  Homebrew::CLI::Parser.new do
    usage_banner <<~EOS
      `license-fetch` [<options>] [<formula>]

      Fetch license information and append it to `report.csv`. Specify formulae
      to fetch license information for only those formulae, or with `--tap` to
      fetch formula information for a single tap.
    EOS
    switch "--rate-limit",
           description: "Rate limit GitHub requests"
    switch "--help-pls",
         description: "Print help"
    flag "--tap=",
         description: "The tap to fetch formula from"
    flag "--github-key=",
         description: "GitHub API key"
    switch :verbose
    switch :debug
    conflicts "--fetch", "--rewrite"
  end
end

def github_full_name(f)
  regex = %r{https?://github\.com/(downloads/)?(?<user>[^/]+)/(?<repo>[^/]+)/?.*}
  match = f.stable.url.match regex
  match ||= f.devel&.url&.match regex
  match ||= f.head&.url&.match regex
  match ||= f.homepage.match regex
  
  return nil unless match
  
  user = match[:user]
  repo = match[:repo].delete_suffix(".git")
  
  "#{user}/#{repo}" 
end

def github_fetch_spdx_id(full_name, api_key, uri_string: nil)
  uri_string ||= "https://api.github.com/repos/#{full_name}"
  uri = URI(uri_string)

  req = Net::HTTP::Get.new(uri)
  req['Accept'] = 'application/vnd.github.v3+json'
  req['Authorization'] = "token #{api_key}"

  res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => true) do |http|
    http.request(req)
  end

  res_dict = JSON.parse(res.body)
  opoo "[#{@full_name}] GitHub message: #{res_dict["message"]}" if res_dict["message"]
  
  return github_fetch_license(full_name, api_key, uri_string: res_dict["url"]) if res_dict["message"] == "Moved Permanently"

  license_dict = res_dict["license"] || {}
  license_dict["spdx_id"]
end

def manual_fetch_spdx_id(f)
  fi = FormulaInstaller.new(f, build_from_source_formulae: [f.full_name])
  fi.ignore_deps = true
  fi.prelude
  fi.fetch

  compressed_path = f.cached_download
  puts compressed_path
  
  raise "Unable to extract #{compressed_path.to_s}" unless extract(compressed_path.to_s)
  
  path = "#{File.dirname(compressed_path)}/#{f.name}-#{f.version}/"
  Licensee.license(path)&.spdx_id
end

def extract(path)
  Dir.chdir File.dirname(path) do
    return system("tar -xf '#{path}'") if path.end_with?(".bz2", ".gz", ".xz", ".tgz")
    return system("unzip -nq '#{path}'") if path.end_with?(".zip", ".jar")
    return false
  end
end

def write_report(file, f, spdx_id, message = nil, description = nil)
  file.write "#{f.name},#{spdx_id || ""},#{message || ""},#{description || ""}\n"
  file.flush
end

args = license_fetch_args.parse

if args.help_pls?
  puts license_fetch_args.generate_help_text
  return
end

if args.github_key.blank?
  opoo <<~EOS
    GitHub key is missing. License information will be fetched manually, which means the script will take longer.
    Use the --github-key flag to enter a GitHub API Key

    https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token
  EOS
end

formulae = if args.tap
  Tap.fetch(args.tap).formula_names.map do |name|
    Formulary.factory name
  end
elsif args.formulae.present?
  args.formulae
else
  Formula.to_a
end


report_file = File.open "report.csv", "a+"

already_processed = Set.new(report_file.readlines.map do |line|
  line.split(",")[0].chomp
end)

stat_processed = 0
stat_start = Time.now
stat_total = formulae.count

formulae.sort { |f, g| f.name <=> g.name }.each do |f|
  if already_processed.include? f.name
    oh1 "Skipping #{f}"
    stat_total -= 1

  elsif f.disabled?
    oh1 "Skipping #{f} because it has been disabled"

    write_report(report_file, f, nil, "disabled")

    stat_total -= 1

  elsif args.github_key.present? && (repo_full_name = github_full_name f)
    oh1 "Fetching GitHub license for #{f}"

    # sleeping 1 second per API call should be enough to avoid rate-limiting issues
    # (3600 seconds / hour) * (hour / 5000 requests) < 1 second / request
    sleep 1 if args.rate_limit?

    spdx_id = github_fetch_spdx_id(repo_full_name, args.github_key)

    write_report(report_file, f, spdx_id, "github")

    stat_processed += 1

  else
    oh1 "Fetching license manually for #{f}"
    
    begin 
      spdx_id = manual_fetch_spdx_id f

      write_report(report_file, f, spdx_id, "")

      stat_processed += 1
    rescue => e
      opoo e
      stat_total -= 1
    end
  end

  unless stat_processed == 0
    linear_eta = stat_start + stat_total.to_f / stat_processed.to_f * (Time.now - stat_start)
    puts "#{stat_processed} / #{stat_total}, "\
          "eta: #{(linear_eta - Time.now).to_i}s, "\
          "time passed: #{(Time.now - stat_start).to_i }s"
  end
end

report_file.close
