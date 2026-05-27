status_sources() {
  echo -n "   软件源: "

  case "${OS_FAMILY}" in
    debian)
      local source_text=""
      source_text="$(grep -RhsE "debian|ubuntu|aliyun|tencent|huawei|tuna|ustc" /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | head -n 20 || true)"
      if grep -qi "aliyun" <<<"${source_text}"; then
        echo -e "${C_CYAN}阿里云${C_RESET}"
      elif grep -qi "tencent" <<<"${source_text}"; then
        echo -e "${C_CYAN}腾讯云${C_RESET}"
      elif grep -qi "huawei" <<<"${source_text}"; then
        echo -e "${C_CYAN}华为云${C_RESET}"
      elif grep -qiE "debian.org|ubuntu.com" <<<"${source_text}"; then
        echo -e "${C_CYAN}官方源${C_RESET}"
      else
        echo -e "${C_YELLOW}未知${C_RESET}"
      fi
      ;;
    arch)
      if grep -qE "aliyun|tencent|huawei|tuna|ustc" /etc/pacman.d/mirrorlist 2>/dev/null; then
        echo -e "${C_CYAN}国内镜像${C_RESET}"
      else
        echo -e "${C_CYAN}默认/未知${C_RESET}"
      fi
      ;;
    alpine)
      if grep -qE "aliyun|tencent|huawei|tuna|ustc" /etc/apk/repositories 2>/dev/null; then
        echo -e "${C_CYAN}国内镜像${C_RESET}"
      else
        echo -e "${C_CYAN}默认/未知${C_RESET}"
      fi
      ;;
    redhat|suse)
      echo -e "${C_YELLOW}未自动管理，避免破坏企业源${C_RESET}"
      ;;
    *)
      echo -e "${C_YELLOW}未知${C_RESET}"
      ;;
  esac
}
