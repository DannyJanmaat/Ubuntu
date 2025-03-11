#!/bin/bash

# Kleuren voor output (worden gebruikt buiten YAD-schermen)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Signal handling toevoegen voor netjes afsluiten
trap cleanup_and_exit SIGINT SIGTERM EXIT

# YAD gemeenschappelijke parameters
YAD_COMMON="--center --window-icon=gtk-preferences --image=applications-system"
YAD_WIDTH="800"
YAD_HEIGHT="600"

# Functie voor netjes afsluiten
cleanup_and_exit() {
  local exit_code=$?
  clear
  if [ $exit_code -ne 0 ]; then
    echo -e "${RED}Script is onderbroken door gebruiker (CTRL+C).${NC}"
    echo -e "${YELLOW}Alle actieve YAD vensters worden gesloten.${NC}"
  fi
  
  # Herstel terminal naar normale modus
  reset
  
  # Log indien nodig
  if [ $exit_code -ne 0 ]; then
    log "Script werd onderbroken door gebruiker via CTRL+C of signaal"
  fi
  
  # Verwijder tijdelijke bestanden indien aanwezig
  rm -f /tmp/yad.* 2>/dev/null
  
  exit $exit_code
}

# Controleer of het script als root draait
if [ "$EUID" -ne 0 ]; then
  yad --error --title="Fout" --text="Dit script moet worden uitgevoerd als root (of met sudo)." --button="OK:1"
  exit 1
fi

# Log directory
LOG_DIR="/var/log/ubuntu-setup"
mkdir -p $LOG_DIR
MAIN_LOG="$LOG_DIR/main.log"

# Functie voor logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$MAIN_LOG"
}

log "Script gestart"

# YAD installeren indien nodig
if ! command -v yad &> /dev/null; then
    apt update
    apt install -y yad
    log "YAD geïnstalleerd"
fi

# Functie voor het tonen van banner in terminal (voor niet-yad schermen)
show_banner() {
  clear
  echo -e "${BLUE}"
  echo "██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗    ███████╗███████╗████████╗██╗   ██╗██████╗ "
  echo "██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║    ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗"
  echo "██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║    ███████╗█████╗     ██║   ██║   ██║██████╔╝"
  echo "██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║    ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ "
  echo "╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝    ███████║███████╗   ██║   ╚██████╔╝██║     "
  echo " ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝     ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     "
  echo -e "${NC}"
  echo -e "${YELLOW}=-=-=-=-=-=-=-=-=-=-=-=-=-= Ubuntu Configuratie Script =-=-=-=-=-=-=-=-=-=-=-=-=-=${NC}"
  echo
}

# Functie om berichten weer te geven in YAD en tegelijk naar log te schrijven
yad_info() {
  local title="$1"
  local message="$2"
  
  log "$title: $message"
  yad $YAD_COMMON --width=500 --height=300 --title="$title" --text="$message" --button="OK:0" --text-align=center
}

# Functie om bevestiging te vragen met YAD
yad_confirm() {
  local title="$1"
  local message="$2"
  
  yad $YAD_COMMON --width=500 --height=200 --title="$title" --text="$message" --button="Nee:1" --button="Ja:0" --text-align=center
  local result=$?
  return $result
}

# Functie om input te vragen met YAD
yad_input() {
  local title="$1"
  local message="$2"
  local default="$3"
  local result
  
  result=$(yad $YAD_COMMON --width=500 --title="$title" --text="$message" --entry --entry-text="$default")
  echo "$result"
}

# Functie voor wachtwoord invoer met YAD
yad_password() {
  local title="$1"
  local message="$2"
  
  yad $YAD_COMMON --width=500 --title="$title" --text="$message" --entry --hide-text
}

# Functie om uit een menu te kiezen met YAD
yad_menu() {
  local title="$1"
  local message="$2"
  shift 2
  local options=("$@")
  local choice
  
  # Bouw menu items
  local menu_items=""
  for ((i=0; i<${#options[@]}; i+=2)); do
    menu_items+="${options[$i]}!${options[$i+1]}\n"
  done
  
  choice=$(echo -e "$menu_items" | yad $YAD_COMMON --width=600 --height=400 \
    --title="$title" --text="$message" \
    --list --column="ID" --column="Optie" --print-column=1 --separator="" \
    --button="Annuleren:1" --button="Selecteren:0")
  local result=$?
  
  if [ $result -ne 0 ]; then
    echo ""
  else
    echo "$choice"
  fi
}

# Functie om meerdere items te selecteren met YAD
yad_multi_select() {
  local title="$1"
  local message="$2"
  shift 2
  local options=("$@")
  
  # Bouw menu items
  local menu_items=""
  for ((i=0; i<${#options[@]}; i+=2)); do
    menu_items+="FALSE!${options[$i]}!${options[$i+1]}\n"
  done
  
  choices=$(echo -e "$menu_items" | yad $YAD_COMMON --width=700 --height=500 \
    --title="$title" --text="$message" \
    --list --column="Selecteer" --column="ID" --column="Beschrijving" \
    --checklist --print-column=2 --separator=" " \
    --button="Annuleren:1" --button="Selecteren:0")
  
  local result=$?
  if [ $result -ne 0 ]; then
    echo ""
  else
    echo "$choices"
  fi
}

# Functie om een formulier te tonen met YAD
yad_form() {
  local title="$1"
  local message="$2"
  shift 2
  local fields=("$@")
  
  yad $YAD_COMMON --width=600 --title="$title" --text="$message" --form "${fields[@]}" \
      --button="Annuleren:1" --button="OK:0"
  
  return $?
}

# Functie voor veilige uitvoer naar een bestand
safe_output() {
  local content="$1"
  local file="$2"
  
  echo "$content" > "$file"
}

# Functie voor systeem updaten
update_system() {
  log "Systeem update gestart"
  
  # Bevestiging vragen
  if ! yad_confirm "Systeem Updaten" "Wil je doorgaan met het updaten van het systeem?"; then
    log "Systeem update geannuleerd door gebruiker"
    return
  fi
  
  # Logs
  local update_log="$LOG_DIR/update_$(date +%Y%m%d%H%M%S).log"
  
  # Maak een YAD progressbar venster
  (
    echo "10"; echo "# Updates ophalen..."
    apt update >> "$update_log" 2>&1
    
    echo "30"; echo "# Systeem upgraden..."
    apt upgrade -y >> "$update_log" 2>&1
    
    echo "50"; echo "# Distributie-upgrade uitvoeren..."
    apt dist-upgrade -y >> "$update_log" 2>&1
    
    echo "70"; echo "# Gefaseerde upgrades installeren..."
    apt -o APT::Get::Always-Include-Phased-Updates=true upgrade -y >> "$update_log" 2>&1
    
    echo "90"; echo "# Onnodige pakketten opruimen..."
    apt autoremove -y >> "$update_log" 2>&1
    apt autoclean >> "$update_log" 2>&1
    
    echo "100"; echo "# Systeem update voltooid"
  ) | yad --progress --auto-close --auto-kill --center --width=500 \
       --title="Systeem Updaten" --text="Updates worden uitgevoerd..." \
       --percentage=0 --button="Annuleren:1"

  local update_status=$?
  if [ $update_status -eq 0 ]; then
    log "Systeem update voltooid"
    yad_info "Systeem Update" "Systeem is bijgewerkt.\n\nDetails zijn opgeslagen in $update_log"
  else
    log "Systeem update geannuleerd door gebruiker"
    yad_info "Systeem Update" "Update proces werd onderbroken."
  fi
}

# Functie voor wijzigen computernaam
change_hostname() {
  log "Computernaam wijzigen gestart"
  
  # Bevestiging vragen
  if ! yad_confirm "Computernaam Wijzigen" "Wil je doorgaan met het wijzigen van de computernaam?"; then
    log "Wijzigen computernaam geannuleerd door gebruiker"
    return
  fi
  
  # Huidige hostname weergeven
  current_hostname=$(hostname)
  log "Huidige computernaam: $current_hostname"
  
  # Nieuwe hostname vragen
  new_hostname=$(yad $YAD_COMMON --width=500 --title="Computernaam" \
      --text="Huidige computernaam: <b>$current_hostname</b>\n\nVoer de nieuwe computernaam in:" \
      --entry --entry-text="$current_hostname")
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$new_hostname" ]; then
    yad_info "Computernaam" "Geen naam ingevoerd of geannuleerd. Computernaam blijft ongewijzigd."
    log "Geen nieuwe computernaam ingevoerd of actie geannuleerd"
    return
  fi
  
  log "Nieuwe computernaam: $new_hostname"
  
  # Hostname wijzigen
  hostnamectl set-hostname "$new_hostname"
  
  # Hosts bestand bijwerken
  sed -i "s/127.0.1.1.*$current_hostname/127.0.1.1\t$new_hostname/g" /etc/hosts
  
  log "Computernaam gewijzigd van $current_hostname naar $new_hostname"
  yad_info "Computernaam" "Computernaam is gewijzigd van\n<b>$current_hostname</b>\nnaar\n<b>$new_hostname</b>\n\nEen herstart kan nodig zijn om de wijziging overal door te laten voeren."
}

# Functie voor wijzigen gebruikerswachtwoord zonder interactief passwd
change_password() {
  log "Gebruikerswachtwoord wijzigen gestart"
  
  # Bevestiging vragen
  if ! yad_confirm "Wachtwoord Wijzigen" "Wil je doorgaan met het wijzigen van een gebruikerswachtwoord?"; then
    log "Wijzigen wachtwoord geannuleerd door gebruiker"
    return
  fi
  
  # Maak een array van gebruikersnamen
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  if [ ${#user_list[@]} -eq 0 ]; then
    yad_info "Wachtwoord Wijzigen" "Geen normale gebruikers gevonden op het systeem."
    log "Geen normale gebruikers gevonden"
    return
  fi
  
  # Bouw menu-opties met gebruikers
  local options=""
  for ((i=0; i<${#user_list[@]}; i++)); do
    options+="${i}!${user_list[$i]}\n"
  done
  
  # Laat gebruiker kiezen
  local selection=$(echo -e "$options" | yad $YAD_COMMON --width=500 --height=400 \
    --title="Gebruiker Selecteren" --text="Kies een gebruiker om het wachtwoord te wijzigen:" \
    --list --column="ID" --column="Gebruiker" --print-column=1 --separator="")
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$selection" ]; then
    log "Gebruikerselectie geannuleerd"
    return
  fi
  
  local username="${user_list[$selection]}"
  log "Geselecteerde gebruiker: $username"
  
  # Vraag wachtwoord via YAD
  password1=$(yad $YAD_COMMON --width=500 --title="Wachtwoord" \
    --text="Voer het nieuwe wachtwoord in voor <b>$username</b>:" \
    --entry --hide-text)
  
  if [ $? -ne 0 ] || [ -z "$password1" ]; then
    log "Wachtwoord invoer geannuleerd of leeg wachtwoord ingevoerd"
    yad_info "Wachtwoord Wijzigen" "Wachtwoord wijzigen geannuleerd of leeg wachtwoord ingevoerd."
    return
  fi
  
  # Vraag bevestiging
  password2=$(yad $YAD_COMMON --width=500 --title="Wachtwoord bevestigen" \
    --text="Voer het wachtwoord nogmaals in:" \
    --entry --hide-text)
  
  if [ $? -ne 0 ] || [ -z "$password2" ]; then
    log "Wachtwoord bevestiging geannuleerd"
    yad_info "Wachtwoord Wijzigen" "Wachtwoord bevestiging geannuleerd."
    return
  fi
  
  # Controleer of wachtwoorden overeenkomen
  if [ "$password1" != "$password2" ]; then
    yad_info "Wachtwoord Wijzigen" "De ingevoerde wachtwoorden komen niet overeen. Probeer het opnieuw."
    log "Wachtwoorden komen niet overeen"
    return
  fi
  
  # Controleer of wachtwoord leeg is
  if [ -z "$password1" ]; then
    yad_info "Wachtwoord Wijzigen" "Leeg wachtwoord is niet toegestaan."
    log "Leeg wachtwoord gedetecteerd"
    return
  fi
  
  # Wijzig wachtwoord met chpasswd
  echo "$username:$password1" | chpasswd
  passwd_exit=$?
  
  if [ $passwd_exit -ne 0 ]; then
    yad_info "Wachtwoord Wijzigen" "Wachtwoord wijzigen is mislukt. Controleer de logs voor meer informatie."
    log "Wachtwoord wijzigen voor $username mislukt met code: $passwd_exit"
  else
    yad_info "Wachtwoord Wijzigen" "Wachtwoord voor <b>$username</b> is succesvol gewijzigd."
    log "Wachtwoord voor $username is succesvol gewijzigd"
  fi
}

# Functie voor netwerkconfiguratie
configure_network() {
  log "Netwerkconfiguratie gestart"
  
  # Bevestiging vragen
  if ! yad_confirm "Netwerkconfiguratie" "Wil je doorgaan met het configureren van het netwerk?\n\nWaarschuwing: Het wijzigen van netwerkinstellingen kan ertoe leiden dat je de verbinding met deze server verliest als je via SSH verbonden bent."; then
    log "Netwerkconfiguratie geannuleerd door gebruiker"
    return
  fi
  
  # Backup maken van netplan configuratie
  log "Backup maken van bestaande netplan configuraties"
  mkdir -p /etc/netplan/backup
  find /etc/netplan -name "*.yaml" -exec cp {} /etc/netplan/backup/ \; 2>/dev/null
  
  # Netwerkinterfaces detecteren
  log "Netwerkinterfaces detecteren"
  mapfile -t interface_list < <(ls /sys/class/net | grep -v lo)
  
  if [ ${#interface_list[@]} -eq 0 ]; then
    yad_info "Netwerkconfiguratie" "Geen netwerkinterfaces gevonden."
    log "Geen netwerkinterfaces gevonden"
    return
  fi
  
  # Bouw menu-opties met interfaces
  local options=""
  for ((i=0; i<${#interface_list[@]}; i++)); do
    # IP-adres ophalen voor elke interface
    local ip_addr=$(ip -4 addr show ${interface_list[$i]} 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    if [ -z "$ip_addr" ]; then
      ip_addr="Geen IP"
    fi
    options+="${i}!${interface_list[$i]}!${ip_addr}\n"
  done
  
  # Laat gebruiker een interface kiezen
  local selection=$(echo -e "$options" | yad $YAD_COMMON --width=600 --height=400 \
    --title="Interface Selecteren" --text="Kies een netwerkinterface om te configureren:" \
    --list --column="ID" --column="Interface" --column="IP" --print-column=1 --separator="")
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$selection" ]; then
    log "Interface selectie geannuleerd"
    return
  fi
  
  local INTERFACE="${interface_list[$selection]}"
  log "Geselecteerde interface: $INTERFACE"
  
  # Huidige netwerkinformatie detecteren
  local CURRENT_IP=$(ip -4 addr show $INTERFACE 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  local CURRENT_CIDR=$(ip -4 addr show $INTERFACE 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | cut -d'/' -f2)
  local MASK="255.255.255.0" # Default
  local NETWORK=""
  local CURRENT_GW=""
  local DNS_SERVERS=""
  
  if [ ! -z "$CURRENT_IP" ]; then
    # CIDR naar subnet mask omzetten
    case "$CURRENT_CIDR" in
      32) MASK="255.255.255.255" ;;
      31) MASK="255.255.255.254" ;;
      30) MASK="255.255.255.252" ;;
      29) MASK="255.255.255.248" ;;
      28) MASK="255.255.255.240" ;;
      27) MASK="255.255.255.224" ;;
      26) MASK="255.255.255.192" ;;
      25) MASK="255.255.255.128" ;;
      24) MASK="255.255.255.0" ;;
      23) MASK="255.255.254.0" ;;
      22) MASK="255.255.252.0" ;;
      21) MASK="255.255.248.0" ;;
      20) MASK="255.255.240.0" ;;
      19) MASK="255.255.224.0" ;;
      18) MASK="255.255.192.0" ;;
      17) MASK="255.255.128.0" ;;
      16) MASK="255.255.0.0" ;;
      15) MASK="255.254.0.0" ;;
      14) MASK="255.252.0.0" ;;
      13) MASK="255.248.0.0" ;;
      12) MASK="255.240.0.0" ;;
      11) MASK="255.224.0.0" ;;
      10) MASK="255.192.0.0" ;;
      9) MASK="255.128.0.0" ;;
      8) MASK="255.0.0.0" ;;
      *) MASK="255.255.255.0" ;;
    esac
    
    # Netwerk-ID berekenen
    IFS=. read -r i1 i2 i3 i4 <<< "$CURRENT_IP"
    IFS=. read -r m1 m2 m3 m4 <<< "$MASK"
    n1=$((i1 & m1))
    n2=$((i2 & m2))
    n3=$((i3 & m3))
    n4=$((i4 & m4))
    NETWORK="$n1.$n2.$n3.$n4"
    
    # Gateway detecteren
    CURRENT_GW=$(ip route | grep default | grep $INTERFACE | awk '{print $3}')
    
    # DNS servers detecteren
    if [ -f "/etc/resolv.conf" ]; then
      DNS_SERVERS=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    fi
    
    network_info="<b>Huidige netwerkconfiguratie voor $INTERFACE:</b>\n"
    network_info+="IP-adres: $CURRENT_IP\n"
    network_info+="Subnet mask: $MASK (/$CURRENT_CIDR)\n"
    network_info+="Netwerk: $NETWORK/$CURRENT_CIDR\n"
    if [ ! -z "$CURRENT_GW" ]; then
      network_info+="Default gateway: $CURRENT_GW\n"
    else
      network_info+="Default gateway: Niet gevonden\n"
    fi
    if [ ! -z "$DNS_SERVERS" ]; then
      network_info+="DNS servers: $DNS_SERVERS\n"
    else
      network_info+="DNS servers: Niet gevonden\n"
    fi
  else
    network_info="<b>Geen IP-configuratie gevonden voor $INTERFACE</b>\n"
  fi
  
  log "Huidige netwerkinformatie: $network_info"
  
  # Toon huidige configuratie in label en laat gebruiker nieuwe instellingen invullen
  local netform=$(yad $YAD_COMMON --width=600 --title="Netwerk Configureren" \
    --text="$network_info\n\nVoer de nieuwe netwerkconfiguratie in:" \
    --form \
    --field="IP-adres:" "$CURRENT_IP" \
    --field="Subnet Mask (bijv. 24 of 255.255.255.0):" "$MASK" \
    --field="Gateway:" "$CURRENT_GW" \
    --field="DNS Server 1:" "$(echo $DNS_SERVERS | awk '{print $1}')" \
    --field="DNS Server 2:" "$(echo $DNS_SERVERS | awk '{print $2}')" \
    --field="Search Domain:" "")
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$netform" ]; then
    log "Netwerkconfiguratie formulier geannuleerd"
    return
  fi
  
  # Parse form output
  IFS='|' read -r IP_ADDRESS SUBNET_INPUT GATEWAY DNS_SERVER DNS_SERVER2 SEARCH_DOMAIN <<< "$netform"
  
  # Subnet mask valideren en converteren
  local SUBNET=""
  if [[ "$SUBNET_INPUT" =~ ^[0-9]+$ ]]; then
    # Controleer of het een geldig CIDR nummer is
    if [ "$SUBNET_INPUT" -ge 1 ] && [ "$SUBNET_INPUT" -le 32 ]; then
      SUBNET="$SUBNET_INPUT"
    else
      yad_info "Netwerkconfiguratie" "Ongeldige CIDR notatie. Moet tussen 1 en 32 zijn."
      log "Ongeldige CIDR notatie: $SUBNET_INPUT"
      return
    fi
  # Als het een subnet mask in dotted decimal is (255.255.255.0)
  elif [[ "$SUBNET_INPUT" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # Converteer subnet mask naar CIDR notatie
    case "$SUBNET_INPUT" in
      255.255.255.255) SUBNET="32" ;;
      255.255.255.254) SUBNET="31" ;;
      255.255.255.252) SUBNET="30" ;;
      255.255.255.248) SUBNET="29" ;;
      255.255.255.240) SUBNET="28" ;;
      255.255.255.224) SUBNET="27" ;;
      255.255.255.192) SUBNET="26" ;;
      255.255.255.128) SUBNET="25" ;;
      255.255.255.0) SUBNET="24" ;;
      255.255.254.0) SUBNET="23" ;;
      255.255.252.0) SUBNET="22" ;;
      255.255.248.0) SUBNET="21" ;;
      255.255.240.0) SUBNET="20" ;;
      255.255.224.0) SUBNET="19" ;;
      255.255.192.0) SUBNET="18" ;;
      255.255.128.0) SUBNET="17" ;;
      255.255.0.0) SUBNET="16" ;;
      255.254.0.0) SUBNET="15" ;;
      255.252.0.0) SUBNET="14" ;;
      255.248.0.0) SUBNET="13" ;;
      255.240.0.0) SUBNET="12" ;;
      255.224.0.0) SUBNET="11" ;;
      255.192.0.0) SUBNET="10" ;;
      255.128.0.0) SUBNET="9" ;;
      255.0.0.0) SUBNET="8" ;;
      254.0.0.0) SUBNET="7" ;;
      252.0.0.0) SUBNET="6" ;;
      248.0.0.0) SUBNET="5" ;;
      240.0.0.0) SUBNET="4" ;;
      224.0.0.0) SUBNET="3" ;;
      192.0.0.0) SUBNET="2" ;;
      128.0.0.0) SUBNET="1" ;;
      *)
        yad_info "Netwerkconfiguratie" "Ongeldige subnet mask. Voer een geldig subnet mask in."
        log "Ongeldige subnet mask: $SUBNET_INPUT"
        return
        ;;
    esac
    log "Subnet mask $SUBNET_INPUT geconverteerd naar /$SUBNET"
  else
    yad_info "Netwerkconfiguratie" "Ongeldige subnet mask. Voer een geldig getal (1-32) of subnet mask (zoals 255.255.255.0) in."
    log "Ongeldige subnet notatie: $SUBNET_INPUT"
    return
  fi
  
  # Validatie en controle
  if [ -z "$IP_ADDRESS" ]; then
    yad_info "Netwerkconfiguratie" "Geen IP-adres ingevoerd. Configuratie geannuleerd."
    log "Geen IP-adres ingevoerd"
    return
  fi
  
  if [ -z "$GATEWAY" ]; then
    yad_info "Netwerkconfiguratie" "Geen gateway ingevoerd. Configuratie geannuleerd."
    log "Geen gateway ingevoerd"
    return
  fi
  
  # Als DNS server 1 leeg is, gebruik de gateway
  if [ -z "$DNS_SERVER" ]; then
    DNS_SERVER="$GATEWAY"
  fi
  
  # Maak de netplan configuratie
  log "Netplan configuratie maken"
  local NETPLAN_FILE="/etc/netplan/01-netcfg.yaml"
  
  local netplan_content="# Netplan configuratie gegenereerd door Ubuntu setup script
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses:
        - $IP_ADDRESS/$SUBNET
      routes:
        - to: 0.0.0.0/0
          via: $GATEWAY
      nameservers:
        addresses:
          - $DNS_SERVER"
  
  if [ ! -z "$DNS_SERVER2" ]; then
    netplan_content+="
          - $DNS_SERVER2"
  fi
  
  if [ ! -z "$SEARCH_DOMAIN" ]; then
    netplan_content+="
        search: [$SEARCH_DOMAIN]"
  fi
  
  # Schrijf configuratie naar bestand
  safe_output "$netplan_content" "$NETPLAN_FILE"
  
  # Corrigeer rechten voor netplan configuratie
  chmod 600 $NETPLAN_FILE
  
  # Netplan genereren
  log "Netplan configuratie genereren"
  netplan generate
  
  # Configuratie samenvatting
  local config_summary="<b>Nieuwe netwerkconfiguratie voor $INTERFACE:</b>\n"
  config_summary+="IP-adres: $IP_ADDRESS/$SUBNET\n"
  config_summary+="Gateway: $GATEWAY\n"
  config_summary+="DNS server(s): $DNS_SERVER"
  if [ ! -z "$DNS_SERVER2" ]; then
    config_summary+=", $DNS_SERVER2"
  fi
  config_summary+="\n"
  if [ ! -z "$SEARCH_DOMAIN" ]; then
    config_summary+="Search domain: $SEARCH_DOMAIN\n"
  fi
  config_summary+="\nConfiguratie is gegenereerd maar nog niet toegepast."
  
  # Toon configuratie
  yad_info "Netwerk Configuratie" "$config_summary"
  
  # Vraag om configuratie toe te passen
  if yad_confirm "Netwerk Toepassen" "Wil je de nieuwe netwerkconfiguratie nu toepassen?\n\nWaarschuwing: Als je via SSH verbonden bent, kan dit je verbinding verbreken."; then
    log "Netplan configuratie toepassen"
    netplan apply
    
    yad_info "Netwerk Configuratie" "Netplan configuratie is toegepast.\n\nAls je verbinding verbroken is, probeer opnieuw te verbinden met het nieuwe IP-adres."
  else
    log "Gebruiker heeft ervoor gekozen om netplan configuratie niet toe te passen"
    yad_info "Netwerk Configuratie" "Netplan configuratie is NIET toegepast.\n\nJe kunt het later handmatig toepassen met:\nsudo netplan apply"
  fi
}

# Functie voor beveiligen van OpenSSH
secure_ssh() {
  log "OpenSSH beveiliging gestart"
  
  # Bevestiging vragen
  if ! yad_confirm "OpenSSH Beveiligen" "Wil je doorgaan met het beveiligen van OpenSSH?\n\nDit proces:\n- Maakt SSH-sleutels aan of gebruikt bestaande sleutels\n- Configureert SSH voor betere beveiliging\n- Kan wachtwoordauthenticatie uitschakelen"; then
    log "OpenSSH beveiliging geannuleerd door gebruiker"
    return
  fi
  
  # Controleren of OpenSSH server is geïnstalleerd
  if ! dpkg -l | grep -q openssh-server; then
    log "OpenSSH server is niet geïnstalleerd"
    if yad_confirm "OpenSSH Installeren" "OpenSSH server is niet geïnstalleerd. Wil je het nu installeren?"; then
      log "OpenSSH server installeren"
      apt update
      apt install -y openssh-server
    else
      yad_info "OpenSSH Beveiligen" "OpenSSH server is nodig om door te gaan. Actie afgebroken."
      log "Gebruiker heeft besloten OpenSSH niet te installeren"
      return
    fi
  fi
  
  # Backup maken van SSH configuratie
  local backup_file="/etc/ssh/sshd_config.backup.$(date +%Y%m%d%H%M%S)"
  log "Backup maken van SSH configuratie naar $backup_file"
  cp /etc/ssh/sshd_config "$backup_file"
  
  # Tabbladweergave maken voor SSH configuratie
  # Tabblad 1: Basisinstellingen - poort en authenticatie
  # Tabblad 2: Geavanceerde instellingen - algoritmes en timeouts
  # Tabblad 3: Sleutels - sleutelgeneratie en -beheer
  
  # Start YAD met tabs
  local ssh_output=$(yad $YAD_COMMON --title="SSH Beveiligen" --width=700 --height=600 \
    --text="<b>SSH Beveiligingsconfiguratie</b>\n\nPas de instellingen aan voor betere beveiliging van SSH." \
    --notebook --key=ssh \
    --tab="Basis Instellingen" \
    --tab="Geavanceerde Instellingen" \
    --tab="SSH Sleutels" \
    --form --tab=Basis\ Instellingen \
      --field="SSH Poort::NUM" "$(grep "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo 22)" \
      --field="Authenticatiemethode:CB" "^Alleen sleutels!Zowel sleutels als wachtwoorden" \
      --field="Root login toestaan:CB" "Nee^!Ja!Alleen met sleutels" \
      --field="Max. aanmeldpogingen::NUM" "3" \
      --field="Toegangstijd (seconden)::NUM" "30" \
    --form --tab=Geavanceerde\ Instellingen \
      --field="X11 forwarding toestaan:CHK" "FALSE" \
      --field="TCP forwarding toestaan:CHK" "FALSE" \
      --field="Agent forwarding toestaan:CHK" "FALSE" \
      --field="Client alive interval (sec)::NUM" "300" \
      --field="Client alive max count::NUM" "2" \
      --field="Versleuteling:CB" "^Strong (chacha20-poly1305, aes256-gcm)!Compatible (extra algoritmes)!Default" \
      --field="MAC algoritmes:CB" "^Strong (SHA-2)!Compatible (extra algoritmes)!Default" \
      --field="Key Exchange algoritmes:CB" "^Strong (curve25519)!Compatible (extra algoritmes)!Default" \
    --form --tab=SSH\ Sleutels)
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$ssh_output" ]; then
    log "SSH configuratie geannuleerd"
    return
  fi
  
  # Parse form output
  IFS='|' read -r \
    SSH_PORT AUTH_METHOD ROOT_LOGIN MAX_TRIES LOGIN_TIME \
    X11_FWD TCP_FWD AGENT_FWD ALIVE_INT ALIVE_COUNT CIPHERS MACS KEXALG \
    <<< "$ssh_output"
  
  # Valideer poort
  if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -lt 1 ] || [ "$SSH_PORT" -gt 65535 ]; then
    yad_info "SSH Beveiliging" "Ongeldige SSH poort opgegeven. Gebruik een getal tussen 1 en 65535."
    log "Ongeldige SSH poort: $SSH_PORT"
    return
  fi
  
  # Nu laten we de gebruiker een sleuteltype kiezen voor een gebruiker
  # Gebruikers ophalen en laten kiezen
  log "Gebruikers ophalen voor SSH sleutels"
  mapfile -t user_list < <(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
  
  if [ ${#user_list[@]} -eq 0 ]; then
    yad_info "OpenSSH Beveiligen" "Geen normale gebruikers gevonden op het systeem."
    log "Geen normale gebruikers gevonden"
    return
  fi
  
  # Bouw menu-opties met gebruikers
  local options=""
  for ((i=0; i<${#user_list[@]}; i++)); do
    options+="${i}!${user_list[$i]}\n"
  done
  
  # Laat gebruiker kiezen
  local selection=$(echo -e "$options" | yad $YAD_COMMON --width=500 --height=400 \
    --title="Gebruiker Selecteren" --text="Kies een gebruiker voor SSH-sleutels:" \
    --list --column="ID" --column="Gebruiker" --print-column=1 --separator="")
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$selection" ]; then
    log "Gebruikerselectie geannuleerd"
    return
  fi
  
  local SSH_USER="${user_list[$selection]}"
  log "Geselecteerde gebruiker voor SSH-sleutels: $SSH_USER"
  
  # Laat de gebruiker sleuteltype kiezen
  local key_type=$(yad $YAD_COMMON --width=500 --title="SSH Sleuteltype" \
    --text="Kies het type SSH-sleutel om te genereren voor <b>$SSH_USER</b>:" \
    --form --field="Sleuteltype:CB" "^ED25519 (aanbevolen)!RSA 4096-bit!ECDSA")
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$key_type" ]; then
    log "Sleuteltypeselectie geannuleerd"
    return
  fi
  
  # Parse key type
  local KEY_TYPE=$(echo "$key_type" | cut -d'|' -f1)
  
  # ED25519 sleutels aanmaken of bestaande gebruiken
  log "SSH sleutels controleren/aanmaken"
  local USER_HOME=$(eval echo ~$SSH_USER)
  local SSH_DIR="$USER_HOME/.ssh"
  
  if [ ! -d "$SSH_DIR" ]; then
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    chown $SSH_USER:$SSH_USER "$SSH_DIR"
  fi
  
  # Genereer de sleutels
  local KEY_FILE=""
  local KEY_PARAMS=""
  
  case "$KEY_TYPE" in
    "ED25519 (aanbevolen)")
      KEY_FILE="$SSH_DIR/id_ed25519"
      KEY_PARAMS="-t ed25519 -a 100"
      ;;
    "RSA 4096-bit")
      KEY_FILE="$SSH_DIR/id_rsa"
      KEY_PARAMS="-t rsa -b 4096"
      ;;
    "ECDSA")
      KEY_FILE="$SSH_DIR/id_ecdsa"
      KEY_PARAMS="-t ecdsa -b 521"
      ;;
  esac
  
  local KEY_GENERATED=0
  
  if [ ! -f "$KEY_FILE" ]; then
    log "Nieuwe SSH sleutels aanmaken: $KEY_TYPE"
    sudo -u $SSH_USER ssh-keygen $KEY_PARAMS -f "$KEY_FILE" -N ""
    KEY_GENERATED=1
    yad_info "SSH Sleutels" "Nieuwe SSH sleutels aangemaakt: $KEY_TYPE"
  else
    log "Bestaande SSH sleutels gevonden: $KEY_FILE"
    yad_info "SSH Sleutels" "Bestaande SSH sleutels worden gebruikt: $KEY_FILE"
  fi
  
  # Zorg ervoor dat de authorized_keys file bestaat en de juiste rechten heeft
  local AUTH_KEYS="$SSH_DIR/authorized_keys"
  if [ ! -f "$AUTH_KEYS" ]; then
    sudo -u $SSH_USER touch "$AUTH_KEYS"
  fi
  
  cat "$KEY_FILE.pub" >> "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  chown $SSH_USER:$SSH_USER "$AUTH_KEYS"
  
  # SSH configuratie aanpassen
  log "SSH configuratie aanpassen"
  
  # Protocol en sleutels
  sed -i 's/^#Protocol 2/Protocol 2/' /etc/ssh/sshd_config
  sed -i 's/^HostKey \/etc\/ssh\/ssh_host_rsa_key/#HostKey \/etc\/ssh\/ssh_host_rsa_key/' /etc/ssh/sshd_config
  sed -i 's/^HostKey \/etc\/ssh\/ssh_host_ecdsa_key/#HostKey \/etc\/ssh\/ssh_host_ecdsa_key/' /etc/ssh/sshd_config
  sed -i 's/^#HostKey \/etc\/ssh\/ssh_host_ed25519_key/HostKey \/etc\/ssh\/ssh_host_ed25519_key/' /etc/ssh/sshd_config
  
  # SSH poort wijzigen
  sed -i "s/^#Port 22/Port $SSH_PORT/" /etc/ssh/sshd_config
  sed -i "s/^Port [0-9]*/Port $SSH_PORT/" /etc/ssh/sshd_config
  
  # Sleutelauthenticatie inschakelen
  sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  
  # Authenticatie methode instellen
  if [ "$AUTH_METHOD" = "Alleen sleutels" ]; then
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    log "Wachtwoordauthenticatie uitgeschakeld"
  else
    sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
    log "Wachtwoordauthenticatie blijft ingeschakeld"
  fi
  
  # Root login
  case "$ROOT_LOGIN" in
    "Nee")
      sed -i 's/^PermitRootLogin .*$/PermitRootLogin no/' /etc/ssh/sshd_config
      ;;
    "Ja")
      sed -i 's/^PermitRootLogin .*$/PermitRootLogin yes/' /etc/ssh/sshd_config
      ;;
    "Alleen met sleutels")
      sed -i 's/^PermitRootLogin .*$/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
      ;;
  esac
  
  # Max aanmeldpogingen en timeout
  sed -i "s/^#MaxAuthTries 6/MaxAuthTries $MAX_TRIES/" /etc/ssh/sshd_config
  sed -i "s/^MaxAuthTries [0-9]*/MaxAuthTries $MAX_TRIES/" /etc/ssh/sshd_config
  
  sed -i "s/^#LoginGraceTime 2m/LoginGraceTime $LOGIN_TIME/" /etc/ssh/sshd_config
  sed -i "s/^LoginGraceTime .*$/LoginGraceTime $LOGIN_TIME/" /etc/ssh/sshd_config
  
  # Overige beveiligingsinstellingen
  sed -i 's/^#PermitEmptyPasswords no/PermitEmptyPasswords no/' /etc/ssh/sshd_config
  sed -i 's/^ChallengeResponseAuthentication yes/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
  
  # Forwarding opties
  if [ "$X11_FWD" = "TRUE" ]; then
    sed -i 's/^X11Forwarding .*/X11Forwarding yes/' /etc/ssh/sshd_config
  else
    sed -i 's/^X11Forwarding .*/X11Forwarding no/' /etc/ssh/sshd_config
  fi
  
  if [ "$TCP_FWD" = "TRUE" ]; then
    sed -i 's/^AllowTcpForwarding .*/AllowTcpForwarding yes/' /etc/ssh/sshd_config
    if ! grep -q "^AllowTcpForwarding" /etc/ssh/sshd_config; then
      echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config
    fi
  else
    sed -i 's/^AllowTcpForwarding .*/AllowTcpForwarding no/' /etc/ssh/sshd_config
    if ! grep -q "^AllowTcpForwarding" /etc/ssh/sshd_config; then
      echo "AllowTcpForwarding no" >> /etc/ssh/sshd_config
    fi
  fi
  
  if [ "$AGENT_FWD" = "TRUE" ]; then
    sed -i 's/^AllowAgentForwarding .*/AllowAgentForwarding yes/' /etc/ssh/sshd_config
    if ! grep -q "^AllowAgentForwarding" /etc/ssh/sshd_config; then
      echo "AllowAgentForwarding yes" >> /etc/ssh/sshd_config
    fi
  else
    sed -i 's/^AllowAgentForwarding .*/AllowAgentForwarding no/' /etc/ssh/sshd_config
    if ! grep -q "^AllowAgentForwarding" /etc/ssh/sshd_config; then
      echo "AllowAgentForwarding no" >> /etc/ssh/sshd_config
    fi
  fi
  
  # Overige beveiligingsinstellingen
  if ! grep -q "^PermitUserEnvironment" /etc/ssh/sshd_config; then
    echo "PermitUserEnvironment no" >> /etc/ssh/sshd_config
  fi
  
  # Sessiebeveiliging
  sed -i "s/^ClientAliveInterval .*/ClientAliveInterval $ALIVE_INT/" /etc/ssh/sshd_config
  if ! grep -q "^ClientAliveInterval" /etc/ssh/sshd_config; then
    echo "ClientAliveInterval $ALIVE_INT" >> /etc/ssh/sshd_config
  fi
  
  sed -i "s/^ClientAliveCountMax .*/ClientAliveCountMax $ALIVE_COUNT/" /etc/ssh/sshd_config
  if ! grep -q "^ClientAliveCountMax" /etc/ssh/sshd_config; then
    echo "ClientAliveCountMax $ALIVE_COUNT" >> /etc/ssh/sshd_config
  fi
  
  # Versleuteling en beveiliging
  case "$CIPHERS" in
    "Strong (chacha20-poly1305, aes256-gcm)")
      if grep -q "^Ciphers" /etc/ssh/sshd_config; then
        sed -i 's/^Ciphers .*/Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com/' /etc/ssh/sshd_config
      else
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com" >> /etc/ssh/sshd_config
      fi
      ;;
    "Compatible (extra algoritmes)")
      if grep -q "^Ciphers" /etc/ssh/sshd_config; then
        sed -i 's/^Ciphers .*/Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr/' /etc/ssh/sshd_config
      else
        echo "Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
      fi
      ;;
    "Default")
      sed -i '/^Ciphers/d' /etc/ssh/sshd_config
      ;;
  esac
  
  case "$MACS" in
    "Strong (SHA-2)")
      if grep -q "^MACs" /etc/ssh/sshd_config; then
        sed -i 's/^MACs .*/MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com/' /etc/ssh/sshd_config
      else
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com" >> /etc/ssh/sshd_config
      fi
      ;;
    "Compatible (extra algoritmes)")
      if grep -q "^MACs" /etc/ssh/sshd_config; then
        sed -i 's/^MACs .*/MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256/' /etc/ssh/sshd_config
      else
        echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256" >> /etc/ssh/sshd_config
      fi
      ;;
    "Default")
      sed -i '/^MACs/d' /etc/ssh/sshd_config
      ;;
  esac
  
  case "$KEXALG" in
    "Strong (curve25519)")
      if grep -q "^KexAlgorithms" /etc/ssh/sshd_config; then
        sed -i 's/^KexAlgorithms .*/KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org/' /etc/ssh/sshd_config
      else
        echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org" >> /etc/ssh/sshd_config
      fi
      ;;
    "Compatible (extra algoritmes)")
      if grep -q "^KexAlgorithms" /etc/ssh/sshd_config; then
        sed -i 's/^KexAlgorithms .*/KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256/' /etc/ssh/sshd_config
      else
        echo "KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256" >> /etc/ssh/sshd_config
      fi
      ;;
    "Default")
      sed -i '/^KexAlgorithms/d' /etc/ssh/sshd_config
      ;;
  esac
  
  # SSH service herstarten
  log "SSH service herstarten"
  systemctl restart ssh
  
  # Sleutelinformatie voor het resultaatscherm voorbereiden
  local ssh_info=""
  ssh_info+="<b>SSH beveiligingsconfiguratie voltooid:</b>\n\n"
  ssh_info+="1. SSH-poort is ingesteld op: $SSH_PORT\n"
  if [ "$AUTH_METHOD" = "Alleen sleutels" ]; then
    ssh_info+="2. Wachtwoordauthenticatie is uitgeschakeld\n"
    ssh_info+="3. Alleen sleutelauthenticatie is toegestaan\n"
  else
    ssh_info+="2. Wachtwoordauthenticatie is ingeschakeld\n"
    ssh_info+="3. Zowel sleutels als wachtwoorden zijn toegestaan\n"
  fi
  
  # Publieke en private sleutels tonen
  local pubkey=$(cat "$KEY_FILE.pub")
  local privkey=$(cat "$KEY_FILE")
  
  # Maak een scherm om de sleutel te tonen en mogelijk te exporteren
  yad $YAD_COMMON --title="SSH Sleutels" --width=800 --height=600 \
    --text="<b>SSH-sleutels voor gebruiker $SSH_USER:</b>\n\nDe volgende sleutels zijn gemaakt of hergebruikt voor $SSH_USER.\nBewaar de private sleutel veilig en plaats de publieke sleutel op de server." \
    --form \
    --field="Publieke sleutel:TXT" "$pubkey" \
    --field="Private sleutel (BEVEILIG DEZE!):TXT" "$privkey" \
    --field="Instructies voor SSH-verbinding vanaf je client:TXT" "1. Bewaar de bovenstaande private sleutel in een bestand op je client (bijv. id_ssh)
2. Stel de juiste rechten in: chmod 600 id_ssh
3. Gebruik het volgende commando om verbinding te maken:
   ssh -i /pad/naar/id_ssh -p $SSH_PORT $SSH_USER@jouw-server-ip"
  
  # Vraag gebruiker of hij de sleutels wil exporteren
  if yad_confirm "SSH Sleutels Exporteren" "Wil je de SSH sleutels exporteren naar bestanden?"; then
    local export_dir=$(yad --file --directory --title="Kies directory voor export")
    if [ -n "$export_dir" ]; then
      echo "$pubkey" > "$export_dir/id_${SSH_USER}_pub.txt"
      echo "$privkey" > "$export_dir/id_${SSH_USER}_priv.txt"
      chmod 600 "$export_dir/id_${SSH_USER}_priv.txt"
      yad_info "SSH Sleutels" "Sleutels geëxporteerd naar:\n$export_dir/id_${SSH_USER}_pub.txt\n$export_dir/id_${SSH_USER}_priv.txt\n\nZorg ervoor dat je de private sleutel veilig bewaart!"
    fi
  fi
  
  log "OpenSSH beveiligingsconfiguratie voltooid"
}

# Functie voor configureren van firewall
configure_firewall() {
  log "Firewall configuratie gestart"
  
  # Bevestiging vragen
  if ! yad_confirm "Firewall Configureren" "Wil je doorgaan met het configureren van de firewall?"; then
    log "Firewall configuratie geannuleerd door gebruiker"
    return
  fi
  
  # Controleren of UFW is geïnstalleerd
  if ! command -v ufw &> /dev/null; then
    log "UFW is niet geïnstalleerd"
    if yad_confirm "UFW Installeren" "UFW (Uncomplicated Firewall) is niet geïnstalleerd. Wil je het nu installeren?"; then
      log "UFW installeren"
      apt update
      apt install -y ufw
    else
      yad_info "Firewall Configureren" "UFW is nodig om door te gaan. Actie afgebroken."
      log "Gebruiker heeft besloten UFW niet te installeren"
      return
    fi
  fi
  
  # Maak notebook met tabbladen voor verschillende aspecten van de firewall
  # Tab 1: Huidige Status
  # Tab 2: Algemene instellingen
  # Tab 3: Standaard services
  # Tab 4: Aangepaste poorten
  # Tab 5: Geavanceerde regels
  
  while true; do
    # Haal huidige firewall status op
    local firewall_status=$(ufw status verbose)
    local firewall_default_in=$(ufw status verbose | grep 'Default:' | head -1 | awk '{print $2}')
    local firewall_default_out=$(ufw status verbose | grep 'Default:' | tail -1 | awk '{print $2}')
    local firewall_enabled=$([[ $(ufw status | head -1) == *"active"* ]] && echo "TRUE" || echo "FALSE")
    
    # Haal open poorten op
    local open_ports=$(ufw status | grep -v '(v6)' | grep ALLOW | sort | awk '{print $1 ":" $2 ":" $3}')
    local ports_list=""
    if [ ! -z "$open_ports" ]; then
      ports_list="Poort!Protocol!Status\n"
      while IFS= read -r line; do
        if [ ! -z "$line" ]; then
          local port=$(echo "$line" | cut -d':' -f1)
          local proto=$(echo "$line" | cut -d':' -f2)
          local status=$(echo "$line" | cut -d':' -f3)
          ports_list+="$port!$proto!$status\n"
        fi
      done <<< "$open_ports"
    else
      ports_list="Geen open poorten gevonden of firewall niet actief."
    fi
    
    # Notebook interface
    local firewall_action=$(yad $YAD_COMMON --title="Firewall Configureren" --width=800 --height=600 \
      --text="<b>Firewall Configuratie</b>\n\nBeheer de instellingen van de Ubuntu Uncomplicated Firewall (UFW)." \
      --notebook --key=firewall \
      --tab="Status" \
      --tab="Algemene Instellingen" \
      --tab="Standaard Services" \
      --tab="Aangepaste Poorten" \
      --tab="Geavanceerde Regels" \
      --form --tab=Status \
        --field="<b>Huidige Firewall Status</b>:LBL" "" \
        --field="Firewall ingeschakeld:CHK" "$firewall_enabled" \
        --field="Default inkomend:RO" "$firewall_default_in" \
        --field="Default uitgaand:RO" "$firewall_default_out" \
        --field="Uitgebreide status:TXT" "$firewall_status" \
      --form --tab=Algemene\ Instellingen \
        --field="Standaard beleid inkomend:CB" "deny^!allow!reject" \
        --field="Standaard beleid uitgaand:CB" "allow^!deny!reject" \
        --field="IPv6 inschakelen:CHK" "TRUE" \
        --field="Logging inschakelen:CHK" "TRUE" \
        --field="Log niveau:CB" "low^!medium!high!full" \
      --list --tab=Standaard\ Services \
        --column="Selecteer":CHK \
        --column="Poort" \
        --column="Service" \
        --column="Protocol" \
        FALSE "80" "HTTP" "tcp" \
        FALSE "443" "HTTPS" "tcp" \
        FALSE "21" "FTP" "tcp" \
        FALSE "22" "SSH" "tcp" \
        FALSE "25" "SMTP" "tcp" \
        FALSE "53" "DNS" "tcp/udp" \
        FALSE "110" "POP3" "tcp" \
        FALSE "143" "IMAP" "tcp" \
        FALSE "3306" "MySQL" "tcp" \
        FALSE "5432" "PostgreSQL" "tcp" \
        --print-all \
      --form --tab=Aangepaste\ Poorten \
        --field="Poort:NUM" "8080" \
        --field="Protocol:CB" "tcp^!udp!both" \
        --field="Beschrijving:" "Aangepaste service" \
        --field="Richting:CB" "inkomend^!uitgaand!beide" \
        --field="Actie:CB" "toestaan^!blokkeren!weigeren" \
      --list --tab=Geavanceerde\ Regels \
        --text="Huidige open poorten:" \
        --column="Poort" \
        --column="Protocol" \
        --column="Status" \
        $(echo -e "$ports_list") \
      --button="Sluiten:1" \
      --button="Firewall Inschakelen/Uitschakelen:2" \
      --button="Service Toevoegen:3" \
      --button="Aangepaste Poort Toevoegen:4" \
      --button="Reset Firewall:5")
    
    local button=$?
    
    # Verwerk de actie op basis van de knop die is ingedrukt
    case $button in
      1) # Sluiten
        log "Firewall configuratie afgesloten"
        break
        ;;
      2) # Firewall in-/uitschakelen
        if [ "$firewall_enabled" = "TRUE" ]; then
          log "Firewall uitschakelen"
          ufw disable
          yad_info "Firewall Status" "Firewall is uitgeschakeld."
        else
          log "Firewall inschakelen"
          ufw --force enable
          yad_info "Firewall Status" "Firewall is ingeschakeld."
        fi
        ;;
      3) # Standaard services toevoegen
        IFS='|' read -r std_services_list <<< "$(echo "$firewall_action" | grep -A 20 "^tab=Standaard" | cut -d'|' -f1-)"
        
        # Verwerk standaard services
        IFS='|' read -ra service_array <<< "$std_services_list"
        for ((i=0; i<${#service_array[@]}; i+=4)); do
          if [ "${service_array[$i]}" = "TRUE" ]; then
            local port="${service_array[$i+1]}"
            local service="${service_array[$i+2]}"
            local protocol="${service_array[$i+3]}"
            
            log "Service toevoegen: $service ($port/$protocol)"
            
            if [ "$protocol" = "tcp/udp" ]; then
              ufw allow $port comment "$service"
            else
              ufw allow $port/$protocol comment "$service"
            fi
            
            yad_info "Service Toegevoegd" "Service $service (poort $port/$protocol) is toegevoegd aan de firewall."
          fi
        done
        ;;
      4) # Aangepaste poort toevoegen
        IFS='|' read -r port protocol description direction action <<< "$(echo "$firewall_action" | grep -A 10 "^tab=Aangepaste" | tail -1)"
        
        if [ -z "$port" ] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
          yad_info "Poort Toevoegen" "Ongeldige poort. Voer een getal in tussen 1 en 65535."
          continue
        fi
        
        # Zet actie om in UFW-commando
        case "$action" in
          "toestaan") cmd="allow" ;;
          "blokkeren") cmd="deny" ;;
          "weigeren") cmd="reject" ;;
          *) cmd="allow" ;;
        esac
        
        # Zet richting om in UFW-commando
        case "$direction" in
          "inkomend") dir="in" ;;
          "uitgaand") dir="out" ;;
          "beide") dir="" ;;
          *) dir="" ;;
        esac
        
        # Zet protocol om in UFW-commando
        if [ "$protocol" = "both" ]; then
          proto=""
        else
          proto="/$protocol"
        fi
        
        log "Aangepaste poort toevoegen: $port$proto ($description), richting: $direction, actie: $action"
        
        # Voer UFW-commando uit
        if [ -z "$dir" ]; then
          ufw $cmd $port$proto comment "$description"
        else
          ufw $cmd $dir $port$proto comment "$description"
        fi
        
        yad_info "Poort Toegevoegd" "Poort $port$proto ($description) is toegevoegd aan de firewall."
        ;;
      5) # Reset Firewall
        if yad_confirm "Reset Firewall" "Wil je de firewall resetten naar standaardinstellingen?\nAlle aangepaste regels worden verwijderd."; then
          log "Firewall resetten"
          ufw --force reset
          ufw default deny incoming
          ufw default allow outgoing
          ufw --force enable
          yad_info "Firewall Reset" "De firewall is gereset naar standaardinstellingen."
        fi
        ;;
      *) # Geannuleerd
        log "Firewall configuratie geannuleerd"
        break
        ;;
    esac
  done
}

# Functie voor installeren van pakketten
install_packages() {
  log "Pakketinstallatie gestart"
  
  # Bevestiging vragen
  if ! yad_confirm "Pakketten Installeren" "Wil je doorgaan met het installeren van pakketten?"; then
    log "Pakketinstallatie geannuleerd door gebruiker"
    return
  fi
  
  # Lijst met veelgebruikte pakketten
  declare -a packages=("net-tools" "htop" "vim" "tmux" "git" "curl" "wget" "unzip" "iptraf-ng" "nmap" "fail2ban" "ncdu" "rsync" "tree" "mc")
  declare -a package_descriptions=(
    "Netwerktools (ifconfig, netstat, etc.)"
    "Verbeterde interactieve procesbewaking"
    "Verbeterde vi teksteditor"
    "Terminal multiplexer"
    "Versiebeheersysteem"
    "Command line tool voor datatransfer"
    "Downloaden van bestanden via het web"
    "Uitpakken van ZIP-archieven"
    "Interactieve netwerkmonitor"
    "Netwerkscanner en beveiligingstool"
    "Bescherming tegen brute force aanvallen"
    "NCurses schijfgebruik analyzer"
    "Bestanden synchroniseren"
    "Directoryboom weergeven"
    "Midnight Commander bestandsbeheerder"
  )
  
  # Bouw opties voor het checklist formulier
  local items=""
  for ((i=0; i<${#packages[@]}; i++)); do
    items+="FALSE!${packages[$i]}!${package_descriptions[$i]}\n"
  done
  
  # Toon het pakket selectie scherm
  selected_list=$(echo -e "$items" | yad $YAD_COMMON --width=700 --height=500 \
    --title="Pakketten Selecteren" --text="Selecteer de pakketten die je wilt installeren:" \
    --list --checklist \
    --column="Selecteer" --column="Pakket" --column="Beschrijving" \
    --button="Annuleren:1" --button="Installeren:0" \
    --print-column=2 --separator=" ")
  
  local result=$?
  if [ $result -ne 0 ] || [ -z "$selected_list" ]; then
    log "Geen pakketten geselecteerd of geannuleerd"
    return
  fi
  
  # Sla geselecteerde pakketten op
  log "Geselecteerde pakketten: $selected_list"
  
  # Extra pakketmogelijkheid
  if yad_confirm "Extra Pakketten" "Wil je handmatig extra pakketten toevoegen?"; then
    local custom_packages=$(yad_input "Extra Pakketten" "Voer de namen van extra pakketten in (gescheiden door spaties):" "")
    if [ ! -z "$custom_packages" ]; then
      selected_list="$selected_list $custom_packages"
      log "Extra pakketten toegevoegd: $custom_packages"
    fi
  fi
  
  # Installeer de pakketten
  if [ ! -z "$selected_list" ]; then
    log "Pakketten installeren: $selected_list"
    
    # Installatie uitvoeren met voortgangsvenster
    (
      echo "10"; echo "# Pakketbronnen bijwerken..."
      apt update > /dev/null 2>&1
      
      echo "30"; echo "# Pakketten downloaden..."
      # Eerste fase van apt install, alleen download
      apt install -y --download-only $selected_list > /dev/null 2>&1
      
      echo "60"; echo "# Pakketten installeren..."
      # Tweede fase, daadwerkelijke installatie
      apt install -y $selected_list > /dev/null 2>&1
      
      echo "100"; echo "# Pakketinstallatie voltooid"
    ) | yad --progress --auto-close --auto-kill --center --width=500 \
         --title="Pakketten Installeren" --text="Pakketten worden geïnstalleerd..." \
         --percentage=0 --button="Annuleren:1"

    local install_status=$?
    if [ $install_status -eq 0 ]; then
      log "Pakketinstallatie voltooid"
      yad_info "Pakketten Installeren" "De volgende pakketten zijn geïnstalleerd:\n\n$selected_list"
    else
      log "Pakketinstallatie geannuleerd door gebruiker"
      yad_info "Pakketten Installeren" "Pakketinstallatie werd onderbroken."
    fi
  else
    log "Geen pakketten om te installeren"
    yad_info "Pakketten Installeren" "Geen pakketten geselecteerd voor installatie."
  fi
}

# Functie voor systeembronnen bekijken
view_resources() {
  log "Systeembronnen bekijken gestart"
  
  # Verzamel systeem informatie
  local hostname=$(hostname)
  local os_info=$(lsb_release -ds 2>/dev/null || cat /etc/*release 2>/dev/null | head -n1 || uname -om)
  local kernel=$(uname -r)
  local uptime=$(uptime -p)
  local cpu_info=$(lscpu | grep "Model name" | sed 's/Model name: *//g')
  local cpu_cores=$(nproc)
  local load_avg=$(uptime | awk -F'load average:' '{print $2}' | xargs)
  local total_mem=$(free -h | awk '/^Mem:/ {print $2}')
  local used_mem=$(free -h | awk '/^Mem:/ {print $3}')
  local free_mem=$(free -h | awk '/^Mem:/ {print $4}')
  
  # Disk info verzamelen
  local disk_info=$(df -h | grep -v "tmpfs\|udev\|loop")
  
  # Netwerk info verzamelen
  local net_interfaces=$(ip -o addr show | grep -v " lo " | awk '{print $2 ": " $4}')
  
  # Top processen verzamelen
  local top_procs=$(ps aux --sort=-%cpu | head -11 | awk '{if (NR>1) {print $1 "!" $2 "!" $3 "!" $4 "!" $11 "!" $12}}')
  
  # Notebook interface voor bronnen
  yad $YAD_COMMON --title="Systeembronnen" --width=800 --height=600 \
    --text="<b>Systeeminformatie en Bronnen</b>\n\nOverzicht van systeem, CPU, geheugen, opslag en processen." \
    --notebook --key=resources \
    --tab="Systeem Info" \
    --tab="CPU & Geheugen" \
    --tab="Opslag" \
    --tab="Netwerk" \
    --tab="Processen" \
    --form --tab=Systeem\ Info \
      --field="Hostname:" "$hostname" \
      --field="Besturingssysteem:" "$os_info" \
      --field="Kernel:" "$kernel" \
      --field="Uptime:" "$uptime" \
      --field="CPU:" "$cpu_info" \
      --field="CPU Cores:" "$cpu_cores" \
    --form --tab=CPU\ \&\ Geheugen \
      --field="CPU Load Average:" "$load_avg" \
      --field="Totaal Geheugen:" "$total_mem" \
      --field="Gebruikt Geheugen:" "$used_mem" \
      --field="Vrij Geheugen:" "$free_mem" \
      --field="Real-time CPU gebruik:":LBL "" \
      --field="":TXT "$(top -bn1 | head -20)" \
    --list --tab=Opslag \
      --text="Schijfgebruik:" \
      --column="Bestandssysteem" \
      --column="Grootte" \
      --column="Gebruikt" \
      --column="Beschikbaar" \
      --column="Gebruik%" \
      --column="Aangekoppeld op" \
      $(echo "$disk_info" | awk '{print $1 "!" $2 "!" $3 "!" $4 "!" $5 "!" $6}') \
    --form --tab=Netwerk \
      --field="Netwerkinterfaces:":LBL "" \
      --field="":TXT "$(ip addr)" \
      --field="Verbindingen:":LBL "" \
      --field="":TXT "$(netstat -tunap | head -20)" \
    --list --tab=Processen \
      --text="Top CPU-processen:" \
      --column="Gebruiker" \
      --column="PID" \
      --column="CPU%" \
      --column="MEM%" \
      --column="Command" \
      --column="Arguments" \
      $(echo "$top_procs" | tr '!' ' ') \
    --button="Vernieuwen:2" \
    --button="Sluiten:1"
  
  log "Systeembronnen bekijken voltooid"
}

# Functie voor schijfbeheer
manage_disks() {
  log "Schijfbeheer gestart"
  
  # Verzamel schijfinformatie
  local disk_list=$(lsblk -dpno NAME,SIZE,MODEL | grep -v loop)
  local mount_points=$(mount | grep ^/dev/ | awk '{print $1 " op " $3 " (" $5 ")"}')
  local fstab_entries=$(cat /etc/fstab | grep -v "^#" | grep -v "^$")
  
  # Functie voor het formatteren van een partitie
  format_partition() {
    local partition=$1
    local fs_type=$(yad $YAD_COMMON --width=400 --title="Formatteren" \
      --text="<b>Kies bestandssysteem:</b>\n\nSelecteer het bestandssysteem voor $partition:" \
      --form --field="Bestandssysteem:CB" "ext4^!xfs!btrfs!ntfs!fat32!exfat")
    
    local result=$?
    if [ $result -ne 0 ] || [ -z "$fs_type" ]; then
      return
    fi
    
    fs_type=$(echo "$fs_type" | cut -d'|' -f1)
    
    local label=$(yad_input "Partitielabel" "Voer een label in voor de partitie (optioneel):" "")
    
    log "Formatteren van $partition met $fs_type"
    
    if yad_confirm "Formatteren Bevestigen" "WAARSCHUWING: Je staat op het punt $partition te formatteren als $fs_type.\n\nAlle gegevens op deze partitie zullen PERMANENT verloren gaan!\n\nWeet je zeker dat je wilt doorgaan?"; then
      # Formatteren op basis van bestandssysteem
      case "$fs_type" in
        "ext4")
          (
            echo "10"; echo "# Partitie ontkoppelen indien nodig..."
            umount $partition 2>/dev/null
            
            echo "30"; echo "# Partitie formatteren als ext4..."
            if [ -z "$label" ]; then
              mkfs.ext4 $partition
            else
              mkfs.ext4 -L "$label" $partition
            fi
            
            echo "100"; echo "# Formatteren voltooid"
          ) | yad --progress --auto-close --auto-kill --center --width=500 \
               --title="Partitie Formatteren" --text="Bezig met formatteren..." \
               --percentage=0 --button="Annuleren:1"
          ;;
        "xfs")
          (
            echo "10"; echo "# Partitie ontkoppelen indien nodig..."
            umount $partition 2>/dev/null
            
            echo "30"; echo "# Partitie formatteren als xfs..."
            if [ -z "$label" ]; then
              mkfs.xfs $partition
            else
              mkfs.xfs -L "$label" $partition
            fi
            
            echo "100"; echo "# Formatteren voltooid"
          ) | yad --progress --auto-close --auto-kill --center --width=500 \
               --title="Partitie Formatteren" --text="Bezig met formatteren..." \
               --percentage=0 --button="Annuleren:1"
          ;;
        "btrfs")
          (
            echo "10"; echo "# Partitie ontkoppelen indien nodig..."
            umount $partition 2>/dev/null
            
            echo "30"; echo "# Partitie formatteren als btrfs..."
            if [ -z "$label" ]; then
              mkfs.btrfs $partition
            else
              mkfs.btrfs -L "$label" $partition
            fi
            
            echo "100"; echo "# Formatteren voltooid"
          ) | yad --progress --auto-close --auto-kill --center --width=500 \
               --title="Partitie Formatteren" --text="Bezig met formatteren..." \
               --percentage=0 --button="Annuleren:1"
          ;;
        "ntfs")
          (
            echo "10"; echo "# Partitie ontkoppelen indien nodig..."
            umount $partition 2>/dev/null
            
            echo "30"; echo "# Partitie formatteren als ntfs..."
            if [ -z "$label" ]; then
              mkfs.ntfs -f $partition
            else
              mkfs.ntfs -f -L "$label" $partition
            fi
            
            echo "100"; echo "# Formatteren voltooid"
          ) | yad --progress --auto-close --auto-kill --center --width=500 \
               --title="Partitie Formatteren" --text="Bezig met formatteren..." \
               --percentage=0 --button="Annuleren:1"
          ;;
        "fat32")
          (
            echo "10"; echo "# Partitie ontkoppelen indien nodig..."
            umount $partition 2>/dev/null
            
            echo "30"; echo "# Partitie formatteren als fat32..."
            if [ -z "$label" ]; then
              mkfs.vfat -F 32 $partition
            else
              mkfs.vfat -F 32 -n "$label" $partition
            fi
            
            echo "100"; echo "# Formatteren voltooid"
          ) | yad --progress --auto-close --auto-kill --center --width=500 \
               --title="Partitie Formatteren" --text="Bezig met formatteren..." \
               --percentage=0 --button="Annuleren:1"
          ;;
        "exfat")
          (
            echo "10"; echo "# Partitie ontkoppelen indien nodig..."
            umount $partition 2>/dev/null
            
            echo "30"; echo "# Controleren of exfat-utils geïnstalleerd is..."
            apt update > /dev/null 2>&1
            apt install -y exfat-utils > /dev/null 2>&1
            
            echo "60"; echo "# Partitie formatteren als exfat..."
            if [ -z "$label" ]; then
              mkfs.exfat $partition
            else
              mkfs.exfat -n "$label" $partition
            fi
            
            echo "100"; echo "# Formatteren voltooid"
          ) | yad --progress --auto-close --auto-kill --center --width=500 \
               --title="Partitie Formatteren" --text="Bezig met formatteren..." \
               --percentage=0 --button="Annuleren:1"
          ;;
      esac
      
      yad_info "Formatteren" "Partitie $partition is geformatteerd als $fs_type."
      log "Partitie $partition is geformatteerd als $fs_type"
    else
      log "Formatteren van $partition geannuleerd door gebruiker"
    fi
  }
  
  # Functie voor het aan-/ontkoppelen van een partitie
  mount_unmount_partition() {
    local partition=$1
    local action=$2
    
    if [ "$action" = "mount" ]; then
      local mount_point=$(yad_input "Aankoppelpunt" "Voer het aankoppelpunt (mount point) in:" "/mnt/data")
      
      if [ -z "$mount_point" ]; then
        log "Geen aankoppelpunt opgegeven"
        return
      fi
      
      # Maak het koppelpunt aan als het niet bestaat
      if [ ! -d "$mount_point" ]; then
        mkdir -p "$mount_point"
      fi
      
      # Koppel de partitie aan
      log "Partitie $partition aankoppelen op $mount_point"
      mount $partition $mount_point
      
      if [ $? -eq 0 ]; then
        yad_info "Partitie Aankoppelen" "Partitie $partition is aangekoppeld op $mount_point."
        
        # Vraag of de koppeling permanent moet zijn
        if yad_confirm "Permanente Koppeling" "Wil je deze koppeling permanent maken zodat de partitie automatisch wordt aangekoppeld bij het opstarten?"; then
          # Haal het bestandssysteem type op
          local fs_type=$(lsblk -no FSTYPE $partition)
          local uuid=$(lsblk -no UUID $partition)
          
          # Voeg toe aan fstab
          echo "UUID=$uuid $mount_point $fs_type defaults 0 2" >> /etc/fstab
          log "Partitie $partition (UUID=$uuid) toegevoegd aan fstab"
          yad_info "Permanente Koppeling" "Partitie $partition is toegevoegd aan /etc/fstab en zal automatisch worden aangekoppeld bij het opstarten."
        fi
      else
        yad_info "Fout" "Kon partitie $partition niet aankoppelen op $mount_point. Controleer of het bestandssysteem geldig is."
        log "Fout bij aankoppelen van partitie $partition op $mount_point"
      fi
    else # unmount
      log "Partitie $partition ontkoppelen"
      umount $partition
      
      if [ $? -eq 0 ]; then
        yad_info "Partitie Ontkoppelen" "Partitie $partition is ontkoppeld."
        
        # Vraag of de partitie ook uit fstab moet worden verwijderd
        if yad_confirm "Permanente Koppeling Verwijderen" "Wil je deze partitie ook verwijderen uit /etc/fstab zodat deze niet meer automatisch wordt aangekoppeld bij het opstarten?"; then
          # Haal UUID op
          local uuid=$(lsblk -no UUID $partition)
          
          # Maak een backup van fstab
          cp /etc/fstab /etc/fstab.backup.$(date +%Y%m%d%H%M%S)
          
          # Verwijder de regel met deze UUID uit fstab
          sed -i "/UUID=$uuid/d" /etc/fstab
          log "Partitie $partition (UUID=$uuid) verwijderd uit fstab"
          yad_info "Permanente Koppeling Verwijderen" "Partitie $partition is verwijderd uit /etc/fstab."
        fi
      else
        yad_info "Fout" "Kon partitie $partition niet ontkoppelen. Mogelijk is de partitie in gebruik."
        log "Fout bij ontkoppelen van partitie $partition"
      fi
    fi
  }
  
  # Functie voor het bekijken van de schijfdetails
  show_disk_details() {
    local disk=$1
    
    # Verzamel informatie over de schijf
    local disk_info=$(lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL,UUID $disk)
    local smart_info=""
    
    # Controleer of smartmontools is geïnstalleerd
    if ! command -v smartctl &> /dev/null; then
      if yad_confirm "SMART Tools Installeren" "Om gedetailleerde schijfinformatie te bekijken, moet smartmontools worden geïnstalleerd. Wil je dit nu installeren?"; then
        apt update
        apt install -y smartmontools
      fi
    fi
    
    # Haal SMART-informatie op als smartctl beschikbaar is
    if command -v smartctl &> /dev/null; then
      smart_info=$(smartctl -a $disk 2>/dev/null || echo "Geen SMART-gegevens beschikbaar")
    else
      smart_info="Installeer smartmontools om SMART-informatie te bekijken."
    fi
    
    # Toon schijfinformatie
    yad $YAD_COMMON --title="Schijfdetails: $disk" --width=800 --height=600 \
      --text="<b>Informatie voor schijf: $disk</b>" \
      --notebook --key=disk-details \
      --tab="Basisinformatie" \
      --tab="SMART-status" \
      --form --tab=Basisinformatie \
        --field="Schijfstructuur:":LBL "" \
        --field="":TXT "$disk_info" \
        --field="Partitietabel:":LBL "" \
        --field="":TXT "$(parted -l $disk 2>/dev/null || echo 'Kon partitietabel niet lezen')" \
      --form --tab=SMART-status \
        --field="SMART-gegevens:":LBL "" \
        --field="":TXT "$smart_info" \
      --button="Sluiten:0"
    
    log "Schijfdetails weergegeven voor $disk"
  }
  
  # Hoofdfunctie voor schijfbeheer
  while true; do
    # Ververs schijf- en partitielijsten
    disk_list=$(lsblk -dpno NAME,SIZE,MODEL | grep -v loop)
    partition_list=$(lsblk -pno NAME,SIZE,FSTYPE,MOUNTPOINT | grep -v loop | grep -v " disk ")
    
    # Bouw lijst van schijven en partities
    local disk_items=""
    while IFS= read -r line; do
      if [ ! -z "$line" ]; then
        disk_items+="$line\n"
      fi
    done <<< "$disk_list"
    
    local partition_items=""
    while IFS= read -r line; do
      if [ ! -z "$line" ]; then
        partition_items+="$line\n"
      fi
    done <<< "$partition_list"
    
    # Maak een notebook interface voor schijfbeheer
    local disk_output=$(yad $YAD_COMMON --title="Schijfbeheer" --width=800 --height=600 \
      --text="<b>Schijfbeheer</b>\n\nBeheer schijven, partities en aankoppelpunten." \
      --notebook --key=diskmanager \
      --tab="Schijven" \
      --tab="Partities" \
      --tab="Aankoppelpunten" \
      --tab="FSTAB Configuratie" \
      --list --tab=Schijven \
        --text="Beschikbare schijven:" \
        --column="Schijfpad" \
        --column="Grootte" \
        --column="Model" \
        $(echo -e "$disk_items") \
        --print-column=1 \
      --list --tab=Partities \
        --text="Beschikbare partities:" \
        --column="Partitiepad" \
        --column="Grootte" \
        --column="Bestandssysteem" \
        --column="Aankoppelpunt" \
        $(echo -e "$partition_items") \
        --print-column=1 \
      --list --tab=Aankoppelpunten \
        --text="Actieve aankoppelpunten:" \
        --column="Apparaat" \
        --column="Aankoppelpunt" \
        --column="Bestandssysteem" \
        --column="Opties" \
        $(mount | grep ^/dev/ | awk '{print $1 "!" $3 "!" $5 "!" $6}') \
        --print-column=1 \
      --form --tab=FSTAB\ Configuratie \
        --field="Huidige FSTAB configuratie:":LBL "" \
        --field="":TXT "$(cat /etc/fstab)" \
      --button="Sluiten:1" \
      --button="Formatteren:2" \
      --button="Aankoppelen:3" \
      --button="Ontkoppelen:4" \
      --button="Schijfinfo:5")
    
    local button=$?
    local selected_item=$(echo "$disk_output" | head -1)
    
    # Verwerk de actie op basis van de knop die is ingedrukt
    case $button in
      1) # Sluiten
        log "Schijfbeheer afgesloten"
        break
        ;;
      2) # Formatteren
        if [ -z "$selected_item" ]; then
          yad_info "Selectie" "Selecteer eerst een partitie om te formatteren."
          continue
        fi
        
        # Controleer of het een partitie is, niet een hele schijf
        if echo "$selected_item" | grep -q "disk"; then
          yad_info "Formatteren" "Selecteer een partitie, niet een volledige schijf om te formatteren."
          continue
        fi
        
        format_partition "$selected_item"
        ;;
      3) # Aankoppelen
        if [ -z "$selected_item" ]; then
          yad_info "Selectie" "Selecteer eerst een partitie om aan te koppelen."
          continue
        fi
        
        # Controleer of de partitie al is aangekoppeld
        if mount | grep -q "^$selected_item "; then
          yad_info "Aankoppelen" "Deze partitie is al aangekoppeld. Ontkoppel deze eerst."
          continue
        fi
        
        mount_unmount_partition "$selected_item" "mount"
        ;;
      4) # Ontkoppelen
        if [ -z "$selected_item" ]; then
          yad_info "Selectie" "Selecteer eerst een partitie om te ontkoppelen."
          continue
        fi
        
        # Controleer of de partitie is aangekoppeld
        if ! mount | grep -q "^$selected_item "; then
          yad_info "Ontkoppelen" "Deze partitie is niet aangekoppeld."
          continue
        fi
        
        mount_unmount_partition "$selected_item" "unmount"
        ;;
      5) # Schijfinfo
        if [ -z "$selected_item" ]; then
          yad_info "Selectie" "Selecteer eerst een schijf of partitie om informatie te bekijken."
          continue
        fi
        
        show_disk_details "$selected_item"
        ;;
      *) # Geannuleerd
        log "Schijfbeheer geannuleerd"
        break
        ;;
    esac
  done
  
  log "Schijfbeheer voltooid"
}
