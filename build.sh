#!/bin/bash
# shellcheck disable=SC1091
set -o posix
WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${WORK_DIR}" || exit 99
source "${WORK_DIR}"/func
datetime=$(date +%Y%m%d%H%M%S)

# 以下是一些可配置的地方
COMPILE_TMP_DIR=/tmp/curl/
openssl_version=3.1.1
openssl_dir="${COMPILE_TMP_DIR}"/openssl-"${openssl_version}"
require_curl_version=7.29.0 # 高于此版本则不用升级
curl_version=curl-7_88_1
curl_dir="${COMPILE_TMP_DIR}"/curl-"${curl_version}"
zlib_version=1.2.13
zlib_dir="${COMPILE_TMP_DIR}"/zlib-"${zlib_version}"
OUTPUT_DIR="${WORK_DIR}"/release
output_version="$(awk -F = '/Version/{print $2;exit}' "${WORK_DIR}"/release-note)"
output_path=${OUTPUT_DIR}/tsc_curl-"${output_version}"-"${datetime}"
mkdir -p "${OUTPUT_DIR}"
rm -f "${OUTPUT_DIR:?}"/*

yum_packages="make \
    patch \
    gcc \
    perl-IPC-Cmd"
# 以上是一些可配置的地方

#######################################
# 检查系统环境
# Globals:
#   yum_packages: 编译要用到的包
#   require_curl_version: 若系统 curl 版本高于此则不升级
# Arguments:
# Outputs:
# Returns:
#   true/false
#######################################
function check_env {
  local log_file ret pkgs pkg sys_curl_version
  # 排除其他程序可能注入这两个配置干扰编译
  unset LD_LIBRARY_PATH PKG_CONFIG_PATH
  ret=true

  log_file=${WORK_DIR}/"${FUNCNAME[0]}"_"${datetime}".log
  LOGINFO "${FUNCNAME[0]}"
  if [[ "$(whoami)" != "root" ]]; then
    LOGERROR 请使用 root 用户或使用 sudo 编译.
    exit 100
  fi
  sys_curl_version="$(str_strip "$(curl --version | awk '{print $2;exit}')")"
  if version_le "${require_curl_version}" "${sys_curl_version}"; then
    LOGSUCCESS 系统自带 curl 版本满足要求无需升级: "${sys_curl_version}"
    exit 0
  fi
  pkgs=$(rpm -qa)
  for pkg in ${yum_packages}; do
    if ! echo "${pkgs}" | grep -w "${pkg}" &>/dev/null; then
      LOGERROR 系统缺少依赖包: "${pkg}"
      ret=false
    fi
  done
  if ! ${ret}; then
    exit "${ret}"
  else
    LOGSUCCESS "${FUNCNAME[0]}"
    export check_env_flag=1
    return 0
  fi
}

#######################################
# 编译 zlib
# Globals:
#   zlib_dir: zlib 安装位置
#   zlib_version: zlib 版本
# Arguments:
# Outputs:
# Returns:
#######################################
function compile_zlib {
  local log_file
  log_file=${WORK_DIR}/"${FUNCNAME[0]}"_"${datetime}".log
  LOGINFO "${FUNCNAME[0]}", 该步骤可能耗时 1-5 分钟.
  # openssl
  mkdir -p "${zlib_dir}"
  rm -rf "${zlib_dir:?}"/*
  tar xzf "${WORK_DIR}"/zlib-${zlib_version}.tar.gz -C ${zlib_dir}/ &&
    cd ${zlib_dir}/zlib-${zlib_version} || exit 99
  LOGINFO 如有异常请返回编译日志: "${log_file}"
  make clean &>/dev/null
  if (./configure --prefix=${zlib_dir} \
    --static &&
    make -j $(($(nproc) + 1)) &&
    make install) &>>"${log_file}"; then
    LOGSUCCESS "${FUNCNAME[0]}"
  else
    LOGERROR "${FUNCNAME[0]}"
    exit 2
  fi
}

#######################################
# 编译 openssl
# Globals:
#   openssl_dir: openssl 安装位置
#   openssl_version: openssl 版本
# Arguments:
# Outputs:
# Returns:
#######################################
function compile_openssl {
  local log_file
  log_file=${WORK_DIR}/"${FUNCNAME[0]}"_"${datetime}".log
  LOGINFO "${FUNCNAME[0]}", 该步骤可能耗时 2-20 分钟.
  # openssl
  mkdir -p "${openssl_dir}"
  rm -rf "${openssl_dir:?}"/*
  tar xzf "${WORK_DIR}"/openssl-${openssl_version}.tar.gz -C ${openssl_dir}/ &&
    cd ${openssl_dir}/openssl-${openssl_version} || exit 99
  LOGINFO 如有异常请返回编译日志: "${log_file}"
  make clean &>/dev/null
  if (./config --prefix=${openssl_dir} \
    --openssldir=${openssl_dir} \
    no-shared &&
    make -j $(($(nproc) + 1)) &&
    make install) &>>"${log_file}"; then
    LOGSUCCESS "${FUNCNAME[0]}"
  else
    LOGERROR "${FUNCNAME[0]}"
    exit 2
  fi
}

#######################################
# 编译 curl
# Globals:
#   curl_dir: curl 安装位置
#   curl_version: curl 版本
# Arguments:
# Outputs:
# Returns:
#######################################
function compile_curl {
  # curl-curl-7_88_1.tar.gz
  local log_file
  log_file=${WORK_DIR}/"${FUNCNAME[0]}"_"${datetime}".log
  LOGINFO "${FUNCNAME[0]}", 该步骤可能耗时 2-10 分钟.
  mkdir -p "${curl_dir}"
  rm -rf "${curl_dir:?}"/*
  tar xzf "${WORK_DIR}"/curl-${curl_version}.tar.gz -C ${curl_dir}/ &&
    cd ${curl_dir}/curl-${curl_version} || exit 99
  LOGINFO 如有异常请返回编译日志: "${log_file}"
  make clean &>/dev/null
  if (patch -p0 <"${WORK_DIR}"/configure.ac.patch &&
    autoreconf -fi &&
    ./configure --prefix=${curl_dir} \
      --without-nss \
      --disable-libcurl-option \
      --disable-ldap \
      --disable-ldaps \
      --disable-rtsp \
      --with-openssl="${openssl_dir}" \
      --with-zlib="${zlib_dir}" \
      --disable-shared \
      --enable-static &&
    make -j $(($(nproc) + 1)) &&
    make install) &>>"${log_file}"; then
    LOGSUCCESS "${FUNCNAME[0]}"
  else
    LOGERROR "${FUNCNAME[0]}"
    exit 3
  fi
  if "${curl_dir}"/bin/curl -V; then
    LOGSUCCESS curl 可用
    \cp "${curl_dir}"/bin/curl "${output_path}"
    LOGSUCCESS "$(md5sum "${output_path}")"
  else
    LOGERROR "curl 不可用"
  fi
}

# 如果没有指定参数, 则执行全量功能,
# 如果仅指定部分参数, 则先执行 check_env, 再依次执行指定功能,
# 注意调用时需注意指定执行功能依赖, 这个须在各功能内实现
if [[ -n "$*" ]]; then
  if [[ "${check_env_flag}" -ne 1 ]]; then
    if check_env; then
      for f in "$@"; do
        $f
      done
    fi
  else
    exit 1
  fi
else
  check_env &&
    compile_openssl &&
    compile_zlib &&
    compile_curl
fi
