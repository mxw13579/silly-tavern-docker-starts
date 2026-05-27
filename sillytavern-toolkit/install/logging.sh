C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'

msg_info() { printf '%b[INFO]%b %s\n' "${C_BLUE}" "${C_RESET}" "$*"; }
msg_ok() { printf '%b[OK]%b %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
msg_warn() { printf '%b[WARN]%b %s\n' "${C_YELLOW}" "${C_RESET}" "$*"; }
fatal() { printf '%b[ERROR]%b %s\n' "${C_RED}" "${C_RESET}" "$*" >&2; exit 1; }
