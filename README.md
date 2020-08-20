# homebrew-license
External hombrew commands to fetch license information and rewrite formulae.

### How it works

There are two commands which work in tandem: 

* `brew license-fetch --github-key=$GITHUB_KEY --tap=user/repo` fetches license information for formula in tap `user/repo` using GitHub, or by downloading the formula and running [licensee](https://github.com/licensee/licensee) gem. It writes the license information to `report.csv`

  The `report.csv` has four columns:

  | Formula Name | License   | GitHub? | Comment (for your use) |
  | ------------ | --------- | ------- | ---------------------- |
  | abcde        | GPL-2.0   |         |                        |
  | youtube-dl   | Unlicense | github  |                        |

  The column labeled `GitHub?` will be empty if the license was fetched manually.

  **If you encounter fatal errors during the license-fetch process:** don't worry. The script has saved the license information to `report.csv`, so once you fix the error the script will pick back up right where it left off. 

  If it's an error you don't want to fix now, you can manually add a blank license for the formula causing trouble by opening `report.csv` and prepending a line with the formula name and a comment detailing the error, something like:

  ```
  troublesome-formula,,,SSL Error
  ```

* `brew license-rewrite` reads `report.csv` and adds license information to each formula

To get help information, run `brew license-fetch --help-pls` or `brew license-rewrite --help-pls`. 

### To maintainers

If you're the maintainer of a homebrew tap and you would like me to add license information, ping me on a GitHub issue or send me an email. I'd be glad to help! Otherwise, if you would like to add it yourself, feel free to install it and run it.

So far, I've helped add license information to

* [homebrew-core](https://github.com/homebrew/homebrew-core) (done as part of the MLH Fellowship)
* [brewsci/bio](https://github.com/brewsci/homebrew-bio)

The script is by no means perfect: not every formula has detectable license information. For formulae that do have a license, the script might not be able to detect the SPDX license, or the formula might have a more specific license than the one the script finds. But, in my experience, more than half of formulae are able to have their license information detected, which *might be a lot of time and effort saved*

## Installation

`license-fetch` and `license-rewrite` depend on [licensee](https://github.com/licensee/licensee) and [parser](https://github.com/whitequark/parser). Since macOS has become strict about not allowing user-installed gems, I workaround this by using Homebrew's vendor Ruby. 

1. Enable Homebrew's vendor Ruby with `$ export HOMEBREW_FORCE_VENDOR_RUBY=1` 
2. Go to `/usr/local/Homebrew/Library/Homebrew/vendor/portable-ruby/current/bin` (take this path with a grain of salt; it may have changed by the time you're reading this)
3. Run `./gem install licensee parser`

To install the commands themselves,

1. `$ brew tap whoiswillma/license`

Homebrew is constantly changing. When you install this, the script might be out of date because Homebrew's parser or the formula installer was updated. In any case, if you encounter a problem with the script, create a GitHub issue or, even better, submit a pull request with a fix!

## Contributing

I'd love it if you could submit a PR to fix or improve the commands! If my instructions are unclear or out of date, or you see a way that could increase the percent of formulae that are detected, I'd appreciate it if you could submit a PR.

