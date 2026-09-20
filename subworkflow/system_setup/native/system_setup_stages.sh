#!/usr/bin/env bash
# system_setup_stages.sh — 单 stage 执行器（由 native/main.py 调用）
#
# 来源迁移自：
#   01.CentOS_System_Configuration/modify_system_config_files.sh
#   01.CentOS_System_Configuration/system_software_installation.sh
#
# 约定：
#   - 全部路径/用户经 CLI 参数传入，禁止写死 train 以外的默认时仍允许 --train-user
#   - --dry-run：只 echo 将执行的命令，不改系统
#   - 真实执行通常需要 root
set -euo pipefail

STAGE="${1:-}"
shift || true

TRAIN_USER=train
TRAIN_HOME=""
BIO_SOFT_ROOT=/opt/biosoft
SYS_SOFT_ROOT=/opt/sysoft
MYSQL_DATADIR=""
SOFTWARE_CACHE=""
HTTP_PORTS=80,8080,3306
BASE_PACKAGES="httpd mariadb mariadb-server mariadb-devel lftp ftp gd gd-devel cmake gsl gsl-devel gnuplot gmp-devel libffi-devel"
DRY_RUN=0
ENABLE_SYSOFT=0

usage() {
  cat <<EOF
用法: $0 <stage> [选项]
stage: configure_repos | install_base_packages | harden_ssh | configure_firewall |
       configure_selinux_limits | configure_user_env | setup_httpd | setup_mariadb |
       prepare_soft_dirs | install_sysoft_runtimes
选项:
  --train-user NAME
  --train-home DIR
  --bio-soft-root DIR
  --sys-soft-root DIR
  --mysql-datadir DIR
  --software-cache DIR
  --http-ports LIST
  --base-packages "pkg ..."
  --dry-run
  --enable-sysoft-runtimes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --train-user) TRAIN_USER="$2"; shift 2 ;;
    --train-home) TRAIN_HOME="$2"; shift 2 ;;
    --bio-soft-root) BIO_SOFT_ROOT="$2"; shift 2 ;;
    --sys-soft-root) SYS_SOFT_ROOT="$2"; shift 2 ;;
    --mysql-datadir) MYSQL_DATADIR="$2"; shift 2 ;;
    --software-cache) SOFTWARE_CACHE="$2"; shift 2 ;;
    --http-ports) HTTP_PORTS="$2"; shift 2 ;;
    --base-packages) BASE_PACKAGES="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --enable-sysoft-runtimes) ENABLE_SYSOFT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] 未知参数: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -n "$STAGE" ]] || { usage; exit 2; }
TRAIN_HOME="${TRAIN_HOME:-/home/${TRAIN_USER}}"
SOFTWARE_CACHE="${SOFTWARE_CACHE:-${TRAIN_HOME}/software}"
MYSQL_DATADIR="${MYSQL_DATADIR:-$(dirname "$TRAIN_HOME")/.mysql}"

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ %s\n' "$*"
  else
    printf '+ %s\n' "$*"
    "$@"
  fi
}

run_sh() {
  # 多行 shell 片段
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '+ sh -c %q\n' "$1"
  else
    printf '+ sh -c …\n'
    sh -c "$1"
  fi
}

pkg_mgr() {
  if command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  else echo dnf
  fi
}

stage_configure_repos() {
  echo "# 配置仓库源（本地 ISO / 镜像）。缺文件则打印提示，不失败退出。"
  local iso="${SOFTWARE_CACHE}/CentOS-*.iso"
  local base_repo="${SOFTWARE_CACHE}/CentOS-Base.repo"
  run_sh "mkdir -p '${SOFTWARE_CACHE}'"
  if compgen -G "$iso" >/dev/null 2>&1 || [[ "$DRY_RUN" -eq 1 ]]; then
    run_sh "echo '[info] 可选：mount ISO 到本地 media 源，见源脚本 system_software_installation.sh'"
  else
    echo "[info] 未找到 ISO（${SOFTWARE_CACHE}/CentOS-*.iso）；跳过本地介质源"
  fi
  if [[ -f "$base_repo" ]] || [[ "$DRY_RUN" -eq 1 ]]; then
    run_sh "mkdir -p /etc/yum.repos.d/bak && echo '[info] 可将 ${base_repo} 安装到 /etc/yum.repos.d/（需人工确认镜像）'"
  else
    echo "[info] 未找到 ${base_repo}；保留系统默认 repo"
  fi
  run_sh "echo \"alias dnflocal='dnf --disablerepo=* --enablerepo=c8-media-AppStream'\" >> '${TRAIN_HOME}/.bashrc' || true"
}

stage_install_base_packages() {
  local mgr
  mgr="$(pkg_mgr)"
  # shellcheck disable=SC2086
  run_sh "${mgr} -y install ${BASE_PACKAGES}"
}

stage_harden_ssh() {
  local conf=/etc/ssh/sshd_config
  run_sh "test -f ${conf}"
  run_sh "perl -p -i.bak -e 's/#RSAAuthentication/RSAAuthentication/' ${conf}"
  run_sh "perl -p -i -e 's/#PubkeyAuthentication/PubkeyAuthentication/' ${conf}"
  run_sh "perl -p -i -e 's/#AuthorizedKeysFile/AuthorizedKeysFile/' ${conf}"
  run_sh "perl -p -i -e 's/.*PermitRootLogin.*/PermitRootLogin no/' ${conf}"
  run_sh "perl -p -i -e 's/.*UseDNS.*/UseDNS no/' ${conf}"
  run_sh "perl -p -i -e 's/GSSAPIAuthentication yes/GSSAPIAuthentication no/' ${conf}"
  run_sh "systemctl restart sshd.service || service sshd restart || true"
}

stage_configure_firewall() {
  IFS=',' read -r -a ports <<< "$HTTP_PORTS"
  local p
  for p in "${ports[@]}"; do
    p="$(echo "$p" | tr -d ' ')"
    [[ -n "$p" ]] || continue
    run_sh "firewall-cmd --add-port=${p}/tcp --permanent || true"
  done
  run_sh "firewall-cmd --reload || systemctl restart firewalld.service || true"
  run_sh "firewall-cmd --list-ports || true"
}

stage_configure_selinux_limits() {
  run_sh "perl -p -i.bak -e 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config || true"
  run_sh "setenforce 0 || true"
  run_sh "grep -q 'soft[[:space:]]\\+nproc' /etc/security/limits.conf || cat >> /etc/security/limits.conf <<'EOF'
*	soft	nproc	10240
*	hard	nproc	102400
*	soft	nofile	10240
*	hard	nofile	102400
*	soft	stack	10240
*	hard	stack	102400
EOF"
}

stage_configure_user_env() {
  run_sh "id '${TRAIN_USER}' >/dev/null"
  run_sh "test -d '${TRAIN_HOME}'"
  # sudoers：给教学用户 NOPASSWD（仅教学机；生产勿用）
  run_sh "grep -q '^${TRAIN_USER}[[:space:]]' /etc/sudoers || perl -i.bak -e 'while (<>) { if (/^root/) { print; print \"${TRAIN_USER}   ALL=(ALL)       NOPASSWD:ALL\\n\"; last; } else { print } }' /etc/sudoers"
  run_sh "grep -q 'PS1=' '${TRAIN_HOME}/.bashrc' || cat >> '${TRAIN_HOME}/.bashrc' <<'EOF'
PS1='\[\e[1;35;1m\][\u@\h \W]\\$ \[\e[00m\]'
alias lh='ls -lh'
alias les='less -S'
EOF"
  run_sh "grep -q 'LD_LIBRARY_PATH=/usr/local/lib' '${TRAIN_HOME}/.bash_profile' || cat >> '${TRAIN_HOME}/.bash_profile' <<'EOF'
export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:\$PKG_CONFIG_PATH
export LD_LIBRARY_PATH=/usr/local/lib/:/usr/local/lib64:\$LD_LIBRARY_PATH
export C_INCLUDE_PATH=/usr/local/include/:\$C_INCLUDE_PATH
EOF"
}

stage_setup_httpd() {
  local conf=/etc/httpd/conf/httpd.conf
  run_sh "test -f ${conf} || echo '[WARN] 无 httpd.conf，请先 install_base_packages'"
  run_sh "grep -q 'Alias /${TRAIN_USER}' ${conf} || cat >> ${conf} <<EOF

Alias /${TRAIN_USER} \"${TRAIN_HOME}\"
<Directory \"${TRAIN_HOME}\">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
</Directory>
EOF"
  run_sh "usermod -aG '${TRAIN_USER}' apache || usermod -aG '${TRAIN_USER}' www-data || true"
  run_sh "chmod 750 '${TRAIN_HOME}' || true"
  run_sh "perl -p -i -e 's/(AddType text\\/html .shtml)/\$1\\nAddType text\\/plain .pl\\nAddType text\\/plain .py\\nAddType text\\/plain .sh/' ${conf} || true"
  run_sh "perl -p -i -e 's/#AddHandler cgi-script .cgi/AddHandler cgi-script .cgi/' ${conf} || true"
  run_sh "systemctl enable --now httpd.service || systemctl enable --now apache2 || true"
}

stage_setup_mariadb() {
  echo "# 注意：源教学脚本含弱口令示例；部署时务必改口令（此处不写入默认密码）。"
  run_sh "mkdir -p '${MYSQL_DATADIR}'"
  run_sh "chown -R mysql:mysql '${MYSQL_DATADIR}' || true"
  run_sh "test -f /etc/my.cnf.d/mariadb-server.cnf && perl -p -i.bak -e 's#^datadir=.*#datadir=${MYSQL_DATADIR}#' /etc/my.cnf.d/mariadb-server.cnf || true"
  run_sh "systemctl enable --now mariadb.service || systemctl enable --now mysqld || true"
  run_sh "echo '[info] 请手动设置 root 口令并为 ${TRAIN_USER}/pasa/blast2go 建账号（见 system_setup.md）'"
}

stage_prepare_soft_dirs() {
  run_sh "mkdir -p '${BIO_SOFT_ROOT}' '${SYS_SOFT_ROOT}'"
  run_sh "chmod 1777 '${BIO_SOFT_ROOT}' '${SYS_SOFT_ROOT}'"
}

stage_install_sysoft_runtimes() {
  if [[ "$ENABLE_SYSOFT" -ne 1 ]]; then
    echo "[SKIP] install_sysoft_runtimes（未 --enable-sysoft-runtimes）"
    return 0
  fi
  echo "# 教学遗留：预编译包解压到 SYS_SOFT_ROOT。现代路线优先 conda/mamba（AGENT.md §7）。"
  run_sh "mkdir -p '${SYS_SOFT_ROOT}' '${SOFTWARE_CACHE}'"
  run_sh "echo '[info] 若缓存中有 gcc-*.tar.gz / Python-*.tar.gz / R-*.tar.gz / jre*.tar.gz，可 tar -C ${SYS_SOFT_ROOT} -xzf …'"
  run_sh "ls -1 '${SOFTWARE_CACHE}' || true"
}

case "$STAGE" in
  configure_repos) stage_configure_repos ;;
  install_base_packages) stage_install_base_packages ;;
  harden_ssh) stage_harden_ssh ;;
  configure_firewall) stage_configure_firewall ;;
  configure_selinux_limits) stage_configure_selinux_limits ;;
  configure_user_env) stage_configure_user_env ;;
  setup_httpd) stage_setup_httpd ;;
  setup_mariadb) stage_setup_mariadb ;;
  prepare_soft_dirs) stage_prepare_soft_dirs ;;
  install_sysoft_runtimes) stage_install_sysoft_runtimes ;;
  *) echo "[ERROR] 未知 stage: $STAGE" >&2; usage; exit 2 ;;
esac
