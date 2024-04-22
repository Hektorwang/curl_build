# readme

## 程序功能

升级 EL6 机器 curl。

## 部署要求

该程序包仅可在 EL6-x86_64 机器上部署，可使用命令 `uname -r` 查看操作系统信息。

## 部署方法

将提供的 `tsc_curl-$version-$releasedate` 文件拷贝到待部署的服务器 `/tmp/` 目录下

```bash
# 在下面填写上传的 tsc_curl 文件路径如 tsc_curl_path=/tmp/tsc_curl-2.0.0-20240430
tsc_curl_path=
chmod +x ${tsc_curl_path}
base_name="$(which curl)"
# 测试新 curl 是否可用
if "${tsc_curl_path}" --version; then
   # 备份操作系统自带 curl 命令
   mv "${base_name}" "${base_name}"_"$(date +%s)".bak
   # 使用提供的 curl 命令替换原系统命令
   \cp "${tsc_curl_path}" "${base_name}"
fi
"${base_name}" -version # 确认输出版本是否大于7.29
```

## 验证方法

安装完成后，执行 `curl --version` 命令确认输出版本是否大于 7.29