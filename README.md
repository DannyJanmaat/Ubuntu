# Ubuntu Setup Tool

Een grafische configuratietool voor Ubuntu-systemen met een moderne YAD-interface.

## Functies

- **Systeemupdate**: Update en upgrade je systeem
- **Computernaam wijzigen**: Wijzig de hostname van je computer
- **Wachtwoordbeheer**: Wijzig gebruikerswachtwoorden
- **Netwerkconfiguratie**: Configureer netwerkinstellingen met netplan
- **SSH-beveiliging**: Beveilig en configureer OpenSSH met geavanceerde opties
- **Firewall configuratie**: Beheer Ubuntu's Uncomplicated Firewall (UFW)
- **Pakketinstallatie**: Installeer vaak gebruikte pakketten
- **Schijfbeheer**: Beheer schijven, partities en aankoppelpunten
- **Systeembronnen bekijken**: Monitor CPU, geheugen, opslag en processen

## Vereisten

- Ubuntu Linux (of Ubuntu-gebaseerde distributie)
- Root- of sudo-rechten
- Basisondersteuning voor GUI (X11 of Wayland)

## Installatie

1. Clone de repository:
   ```bash
   git clone https://github.com/jouw-username/ubuntu-setup.git
   ```

2. Maak het script uitvoerbaar:
   ```bash
   chmod +x ubuntu-setup.sh
   ```

3. Voer het script uit:
   ```bash
   ./ubuntu-setup.sh
   ```
   Het script zal automatisch om root-rechten vragen als het nodig is.

## Veiligheid

Dit script wijzigt systeeminstellingen en vereist root-rechten. Bekijk altijd de code voordat je scripts met root-rechten uitvoert.

## Bijdragen

Bijdragen zijn welkom! Voel je vrij om pull requests te maken of problemen te melden via GitHub issues.

## Licentie

[MIT](LICENSE)
