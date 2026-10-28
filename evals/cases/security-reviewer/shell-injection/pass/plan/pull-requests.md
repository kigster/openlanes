# Pull Requests

| Pull Request Number | Pull Request Name | Status |
| ------------------: | :---------------- | -----: |
| 21 | [[001.00] Order export](https://github.com/example/shop/pull/21) | Open 🟡 |

## Findings: security-reviewer

### F101 [critical] lib/export.rb:3

💣 Shell injection: `name` comes from the request and is interpolated into `system("tar ...")` unescaped. Failing scenario: `Export.new.call("x; rm -rf ~")` is expected to archive under one odd name, and actually runs `rm -rf ~` as a second command. Pass the arguments as a list, `system("tar", "-czf", "exports/#{name}.tgz", "data/")`, and reject a `name` that is not `/\A[\w-]+\z/`, since `../` still escapes `exports/`.

> [!NOTE]
>
> [2026-10-28 05:00:00 PM PDT] [ agent: security-reviewer  status: Started, round 1 ]
> [2026-10-28 05:02:40 PM PDT] [ agent: security-reviewer  status: Completed, round 1 (rejected 1/2, vulnerability) ]
