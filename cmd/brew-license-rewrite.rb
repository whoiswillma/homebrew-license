require 'parser/current'

def license_rewrite_args
  Homebrew::CLI::Parser.new do
    usage_banner <<~EOS
        `license` [<options>]

        Get or modify the licenses of formulae.
    EOS
    switch :verbose
    switch :debug
  end
end

def rewrite_formulae(formulae, args:)
  Parser::Builders::Default.emit_lambda = true
  Parser::Builders::Default.emit_procarg0 = true
  Parser::Builders::Default.emit_encoding = true
  Parser::Builders::Default.emit_index = true
  Parser::Builders::Default.emit_arg_inside_procarg0 = true
  Parser::Builders::Default.emit_forward_arg = true

  report_file = File.open "report.csv", "r"
  name_to_license = Hash.new
  report_file.readlines.each do |line|
    components = line.split(",")
    name_to_license[components[0]] = components[1] unless components[1] == "" || components[1] == "NOASSERTION"
  end
  report_file.close

  formulae.each do |f|
    rewrite_formula name_to_license, f, args: args
  end
end

def rewrite_formula(name_to_license, formula, args:)
  return unless name_to_license.has_key?(formula.name)

  formula_contents = File.open(formula.path).read
  ast = Parser::CurrentRuby.parse formula_contents
  body = bfs(ast) { |node| node.type == :class }.children.last
  odie "Fail: #{formula.name}: #{ast}" unless body.type == :begin

  after = body.children.find { |node| node.type == :send && node.children[1] == :sha256 }
  after ||= body.children.find { |node| node.type == :send && node.children[1] == :version }
  after ||= body.children.find { |node| node.type == :send && node.children[1] == :mirror }
  after ||= body.children.find { |node| node.type == :send && node.children[1] == :url }
  after ||= body.children.find { |node| node.type == :send && node.children[1] == :homepage }
  after ||= body.children.find { |node| node.type == :send && node.children[1] == :desc }
  after ||= body.children.find { |node| node.type == :send && node.children[1] == :include }

  formula_file = File.open formula.path
  lines = formula_file.readlines
  formula_file.close

  if lines.any? { |line| line.match /\A\s\slicense/ }
    puts "#{formula} already contains a license clause"
    return
  end

  if after
    lines.insert(after.location.expression.end.line, "  license \"#{name_to_license[formula.name]}\"\n")

    formula_file = File.open formula.path, "w"
    lines.each { |line| formula_file.write line }
    formula_file.close
    
    puts "Added license #{name_to_license[formula.name]} to #{formula}" if args.verbose?
  else
    ofail "Could not find after node"
  end
end

def bfs(node)
  q = [node]
  until q.empty?
    n = q.shift
    return n if yield n
    q += n.children
  end
  nil
end

args = license_rewrite_args.parse

formulae = if args.tap
  Tap.fetch(args.tap).formula_names.map do |name|
    Formulary.factory name
  end
elsif args.formulae.present?
  args.formulae
else
  Formula.to_a
end

rewrite_formulae(formulae, args: args)
