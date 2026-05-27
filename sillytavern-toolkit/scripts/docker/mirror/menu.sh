#!/usr/bin/env bash

print_docker_mirror_menu_header() {
  local title="${1:-Docker 镜像加速器管理}"
  local description="${2:-候选源来自固定推荐项和 OpsNote 监控页，写入前会要求确认。}"

  clear || true
  echo "${DOCKER_MIRROR_MENU_SEP}"
  echo "SillyTavern Docker 工具箱 | FuFu API | 群 1019836466"
  echo "${DOCKER_MIRROR_MENU_SEP}"
  echo "${title}"
  echo "${description}"
  echo "${DOCKER_MIRROR_MENU_SEP}"
}


print_mirror_speed_result() {
  local result="$1"
  local time code mirror

  IFS=$'\t' read -r time code mirror <<<"${result}"
  if [[ "${time}" == "9999.999" ]]; then
    printf '%-8s %-4s %s\n' "失败" "${code}" "${mirror}"
  else
    printf '%-9s %-4s %s\n' "${time}s" "${code}" "${mirror}"
  fi
}


print_mirror_http_hint() {
  msg_info "说明：HTTP 401 表示 Docker Registry /v2/ 可达但未认证，通常代表网络可达。"
}


speed_test_current_mirrors() {
  local mirrors=()
  mapfile -t mirrors < <(get_current_docker_mirrors)

  if ((${#mirrors[@]} == 0)); then
    msg_warn "当前未配置 Docker 镜像加速器，将测试原生 Docker Hub 访问。"
    print_mirror_http_hint
    printf '%-9s %-4s %s\n' "耗时" "HTTP" "地址"
    print_mirror_speed_result "$(measure_docker_hub_native)"
    return 0
  fi

  msg_info "正在测速当前 registry-mirrors..."
  print_mirror_http_hint
  printf '%-9s %-4s %s\n' "耗时" "HTTP" "地址"

  local mirror normalized result
  local valid_mirrors=()
  for mirror in "${mirrors[@]}"; do
    if normalized="$(normalize_mirror_url "${mirror}")"; then
      valid_mirrors+=("${normalized}")
    else
      printf '%-8s %-4s %s\n' "无效" "-" "${mirror}"
    fi
  done

  while IFS= read -r result; do
    [[ -n "${result}" ]] || continue
    print_mirror_speed_result "${result}"
  done < <(measure_mirrors_concurrent "${valid_mirrors[@]}")
}


mirror_menu_label() {
  local mirror="$1"
  local rank="$2"
  local label="${mirror#https://}"

  if [[ "${mirror}" == "${DOCKER_DEFAULT_MIRROR}" ]]; then
    if [[ "${rank}" == "1" ]]; then
      label="腾讯云（默认，最快）"
    else
      label="腾讯云（默认）"
    fi
  elif [[ "${rank}" == "1" ]]; then
    label="${label}（最快）"
  fi

  printf '%s\n' "${label}"
}


select_docker_mirror_interactive() {
  ensure_interactive_tty

  local sorted=()
  mapfile -t sorted < <(build_mirror_options)

  local menu_mirrors=()
  local menu_results=()
  local menu_labels=()
  local failed_results=()
  local result time code mirror

  for result in "${sorted[@]}"; do
    IFS=$'\t' read -r time code mirror <<<"${result}"
    if mirror_probe_failed "${time}" "${code}"; then
      failed_results+=("${result}")
      continue
    fi

    if ((${#menu_mirrors[@]} < 6)); then
      menu_mirrors+=("${mirror}")
      menu_results+=("${result}")
      menu_labels+=("$(mirror_menu_label "${mirror}" "${#menu_mirrors[@]}")")
    fi
  done

  print_docker_mirror_menu_header "选择 Docker Hub 镜像加速器" "按本次测速结果排序；写入前会再次确认。"
  print_mirror_http_hint
  if ((${#menu_mirrors[@]} == 0)); then
    msg_warn "本次未发现测速成功的候选镜像，可选择自定义输入。"
  fi

  local i label display_time display_code
  for i in "${!menu_mirrors[@]}"; do
    IFS=$'\t' read -r display_time display_code mirror <<<"${menu_results[$i]}"
    display_time="${display_time}s"
    label="${menu_labels[$i]}"

    printf '%2d. %-28s %-10s HTTP %-3s %s\n' "$((i + 1))" "${label}" "${display_time}" "${display_code}" "${menu_mirrors[$i]}"
  done

  if ((${#failed_results[@]} > 0)); then
    echo
    echo "不可用候选（本次不推荐）："
    for result in "${failed_results[@]}"; do
      IFS=$'\t' read -r _ display_code mirror <<<"${result}"
      label="$(mirror_menu_label "${mirror}" "-")"
      printf '    %-28s %-10s HTTP %-3s %s\n' "${label}" "失败" "${display_code}" "${mirror}"
    done
  fi

  local custom_index cancel_index
  custom_index=$((${#menu_mirrors[@]} + 1))
  cancel_index=0
  printf '%2d. 自定义输入\n' "${custom_index}"
  printf '%2d. 取消\n' "${cancel_index}"

  local choice selected=""
  while true; do
    read -r -p "请输入选项 [0-${custom_index}]: " choice </dev/tty
    if [[ "${choice}" == "0" ]]; then
      msg_warn "已取消。"
      return 0
    elif [[ "${choice}" == "${custom_index}" ]]; then
      read -r -p "请输入自定义 HTTPS 镜像加速器地址: " selected </dev/tty
      selected="$(normalize_mirror_url "${selected}")" || {
        msg_warn "地址格式无效，必须是 HTTPS URL，且不能包含空格或 shell 特殊字符。"
        continue
      }
      break
    elif [[ "${choice}" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#menu_mirrors[@]})); then
      selected="${menu_mirrors[$((choice - 1))]}"
      break
    else
      msg_warn "无效选项。"
    fi
  done

  echo
  msg_info "已选择: ${selected}"
  local selected_result selected_time selected_code
  selected_result="$(measure_mirror "${selected}")"
  print_mirror_speed_result "${selected_result}"
  IFS=$'\t' read -r selected_time selected_code _ <<<"${selected_result}"

  local answer=""
  if mirror_probe_failed "${selected_time}" "${selected_code}"; then
    msg_warn "该镜像本次测速失败，默认不会写入。HTTP ${selected_code:-000} 通常表示该地址当前不可用或无法完成 /v2/ 探测。"
    read -r -p "如仍要写入，请输入 yes 或 YES: " answer </dev/tty
    if [[ "${answer}" != "yes" && "${answer}" != "YES" ]]; then
      msg_warn "已取消写入。"
      return 0
    fi
  else
    read -r -p "确认写入 /etc/docker/daemon.json？(y/n): " answer </dev/tty
    case "${answer}" in
      [Yy]*) ;;
      *)
        msg_warn "已取消写入。"
        return 0
        ;;
    esac
  fi

  write_docker_mirrors "${selected}"
  msg_ok "Docker 镜像加速器已更新为: ${selected}"
  confirm_docker_restart
}


remove_docker_mirrors_interactive() {
  ensure_interactive_tty
  show_docker_mirror_config

  local answer=""
  read -r -p "确认移除 registry-mirrors 配置？(y/n): " answer </dev/tty
  case "${answer}" in
    [Yy]*)
      remove_docker_mirrors
      msg_ok "Docker 镜像加速器配置已移除。"
      confirm_docker_restart
      ;;
    *)
      msg_warn "已取消。"
      ;;
  esac
}


docker_mirror_menu() {
  ensure_interactive_tty

  local choice=""
  while true; do
    print_docker_mirror_menu_header
    show_docker_mirror_config
    echo "${DOCKER_MIRROR_MENU_SEP}"
    echo "   1. 查看当前配置"
    echo "   2. 测速当前配置"
    echo "   3. 选择/更换镜像加速器"
    echo "   4. 移除镜像加速器"
    echo "   0. 返回"
    echo "${DOCKER_MIRROR_MENU_SEP}"
    read -r -p "请输入选项 [0-4]: " choice </dev/tty

    case "${choice}" in
      1) show_docker_mirror_config; pause_to_continue ;;
      2) speed_test_current_mirrors; pause_to_continue ;;
      3) select_docker_mirror_interactive; pause_to_continue ;;
      4) remove_docker_mirrors_interactive; pause_to_continue ;;
      0) break ;;
      *) msg_warn "无效选项。"; pause_to_continue ;;
    esac
  done
}

