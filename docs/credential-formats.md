# 凭据格式

`ferret9 inspect <文件>` 只识别，不入库。它印出的名称才是 `add` 要写的那个名称。名称不是你随便起的：按文件名加上这一节里的后缀生成，必须和识别结果一致，否则 `add` 报找不到。

`run` 不读库里的密钥。它按类型到固定目录再识别一次，用同一个名称对上才执行。源文件改名、挪走，或当时不是从这些目录识别的，库里还有记录，`run` 也会报「源文件」找不到。

| 类型 | `run` 再找的目录 | 代发 |
|------|------------------|------|
| kubeconfig | `~/.kube` | `kubectl` |
| aliyun | `~/.aliyun` | `aliyun` |
| aws | `~/.aws` | `aws` |
| cloudflare | `~/.cloudflare` | `curl` |
| feishu | `~/.feishu` | `curl` |
| private-key | `~/.ssh` | `ssh`、`ssh-keygen` |
| github | `~/.github` | `gh` |
| ossutil、redis | 不代发 | `run` 拒绝 |

编码按 UTF-8、GB18030、Latin-1 依次试。除 PEM 外，空行或单独一行的 `---` 会把文件拆成多段，每段单独识别。同一段可以命中多种，按生成的名称去重。

文件名先去掉开头的点，再去掉 `yaml`、`yml`、`json`、`txt`、`pem`、`ini`、`cfg`、`conf`。`@` 换成 `-at-`。入库名称首字符必须是字母或数字，其余只能是字母、数字、`.`、`_`、`-`，总长不超过 81。

下面的值都是占位，不要把真密钥写进仓库或对话。

## kubeconfig

必须同时有 `apiVersion:`，以及 `clusters:` 或 `kind: Config`。整段原文存下来。有 `current-context:` 时，说明里用这个 context；没有就当 `default`。没有 `contexts:` 时，置信度是中。

名称等于文件名。`~/.kube/config` 的名称是 `config`。

```yaml
apiVersion: v1
kind: Config
current-context: lab
clusters:
  - name: lab
contexts:
  - name: lab
```

## aliyun

两种都认。

官方配置是一个 JSON 对象，或对象数组。对象里要有 `profiles`。每个 profile 要有 `access_key_id` 和 `access_key_secret`。`name` 缺省是 `default`，`region_id` 可空。字段名不区分大小写。

名称是 `<文件名>-<profile 名>`。有 `current` 且 profile 多于一个时，只留名称以 `-<current>` 结尾的那条。

```json
{
  "current": "default",
  "profiles": [
    {
      "name": "default",
      "mode": "AK",
      "access_key_id": "LTAIexample",
      "access_key_secret": "secret-example",
      "region_id": "cn-hangzhou"
    }
  ]
}
```

`~/.aliyun/config.json` 配上面这份，名称是 `config-default`。

没有 `profiles` 的 JSON，只要某处同时有这两个字段，也收成 aliyun，名称就是文件名，置信度中。

环境变量文件认这四对，名称是 `<文件名>-<下表后缀>`：

| 变量 | 后缀 | 类型 |
|------|------|------|
| `ALIBABA_CLOUD_ACCESS_KEY_ID` / `SECRET` | `alibaba_cloud` | aliyun |
| `ALICLOUD_ACCESS_KEY_ID` / `SECRET` | `alicloud` | aliyun |
| `ALICLOUD_ACCESS_KEY_ID_PUBLIC` / `SECRET_PUBLIC` | `alicloud_public` | aliyun |
| `ALICLOUD_ACCESS_KEY_ID_PRIVATE` / `SECRET_PRIVATE` | `alicloud_private` | aliyun |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | `aws` | aws |

一行一个 `KEY=value`，可加 `export`，可加引号。`#` 和 `;` 开头是注释。

## aws

INI。段名用方括号。段内要有 `aws_access_key_id` 和 `aws_secret_access_key`，键名不区分大小写。名称是 `<文件名>-<段名>`。

```ini
[default]
aws_access_key_id = AKIAexample
aws_secret_access_key = secret-example
```

`~/.aws/credentials` 的名称是 `credentials-default`。同一段如果先匹配上这对 AWS 键，就不会再当成 ossutil。

也认上面那对 `AWS_ACCESS_KEY_ID` 环境变量。

## ossutil

INI。段内是 `accessKeyID` 与 `accessKeySecret`，或 `access_key_id` 与 `access_key_secret`。`endpoint` 只进说明。名称是 `<文件名>-<段名>`。能入库，没有代发。

```ini
[default]
accessKeyID=LTAIexample
accessKeySecret=secret-example
endpoint=oss-cn-hangzhou.aliyuncs.com
```

## cloudflare

文本里要有 `api-token`，并且有 `accounts:` 列表。每一项是若干 `键: 值`，不是任意 YAML。`api-token` 至少 8 个字符。`name` 缺省 `default`，`@` 会变成 `-at-`。名称是 `<文件名>-<name>`。

```yaml
accounts:
  - name: lab
    api-token: token-example-0123456789
    api-token-name: dns-read
```

`run` 只在 `~/.cloudflare` 里找这份文件。

## feishu

JSON。必须有 `app_secret`，至少 8 个字符。`app_id` 可空，但空的不能代发。名称等于文件名。

```json
{
  "app_id": "cli_example",
  "app_secret": "secret-example"
}
```

## redis

能入库，没有代发。文本里要有 `password:`，并有 `instances:`。实例名比 `instances:` 多缩进两格，单独成行，以冒号结尾，中间不能有空格。密码至少 6 个字符。可写 `host`、`region`、`user`。名称是 `<文件名>-<实例名>`。

```yaml
instances:
  lab:
    host: 127.0.0.1
    region: dev
    user: default
    password: secret-example
```

## private-key

整份文件同时含 `-----BEGIN ` 和 `PRIVATE KEY`。空行不会被拆掉。OpenSSH 和 PKCS#8 都满足。名称等于文件名。`~/.ssh/id_ed25519` 的名称是 `id_ed25519`。

```text
-----BEGIN OPENSSH PRIVATE KEY-----
正文
-----END OPENSSH PRIVATE KEY-----
```

## github

三种来源，类型都是 `github`。代发只交给 `gh`，而且源文件必须在 `~/.github`。`sk-` 能入库，不能代发。

正文里出现 `ghp_` 加至少 20 位字母数字，名称是 `<文件名>-github-1`。`sk-` 加至少 20 位字母数字，名称是 `<文件名>-openai-1`。各只取第一处。

环境变量文件里，这些键的值至少 8 个字符也收成 github：`API_KEY`、`TOKEN`、`ACCESS_TOKEN`、`token_value`、`apikey`、`api_key`、`value`。名称是 `<文件名>-<键名小写>`。键是 `value` 时，说明用同一文件里的 `name`。
