# Star-DLP

Star-DLP (Star Downloader) 是一个 Ruby gem，用于下载和管理您在 GitHub 上标星的仓库。它支持将星标仓库下载为 JSON 和 Markdown 文件，并且支持增量下载，只下载本地没有的新星标仓库。

## 安装

添加这一行到您的应用程序的 Gemfile:

```ruby
gem 'star-dlp'
```

然后执行:

```bash
$ bundle install
```

或者自己安装:

```bash
$ gem install star-dlp
```

## 使用方法

### 配置

首先，您可以配置 Star-DLP:

```bash
$ star-dlp config --token=your_github_token
```

您可以设置以下选项:
- `--token`: GitHub API 令牌 (推荐使用，以避免 API 速率限制)
- `--output_dir`: 输出目录
- `--json_dir`: JSON 文件目录
- `--markdown_dir`: Markdown 文件目录

### 下载星标仓库

要下载您的星标仓库:

```bash
$ star-dlp download your_github_username
```

这将下载您所有的星标仓库，并将它们保存为 JSON 和 Markdown 文件。如果您之前已经下载过一些仓库，它只会下载新的星标仓库。

### 查看版本

```bash
$ star-dlp version
```

## 文件结构

Star-DLP 将文件保存在以下位置:

- 配置文件: `~/.star-dlp/config.json`
- 星标仓库: `~/.star-dlp/stars/`
  - JSON 文件: `~/.star-dlp/stars/json/`
  - Markdown 文件: `~/.star-dlp/stars/markdown/`

## 开发

克隆仓库后，运行 `bin/setup` 安装依赖项。然后，运行 `rake spec` 运行测试。您也可以运行 `bin/console` 进入交互式提示符，允许您进行实验。

要安装此 gem 到您的本地机器，运行 `bundle exec rake install`。

## 贡献

欢迎 Bug 报告和拉取请求。本项目旨在成为一个安全、友好的协作空间，贡献者需要遵守行为准则。

## 许可证

该 gem 可在 [MIT 许可证](https://opensource.org/licenses/MIT)下使用。
