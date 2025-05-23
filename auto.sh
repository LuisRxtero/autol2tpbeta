#!/bin/bash
# AutoL2TP - Script de instalación y gestión para L2TP/IPsec
# Soporta: PAP, CHAP, MS-CHAPv1, MS-CHAPv2, IPv6
# Requiere root

# Configuración inicial
IPSEC_SECRET="tu_clave_ipsec"
DNS_SERVERS="8.8.8.8 8.8.4.4"
IPV4_POOL="10.0.2.100-10.0.2.200"
IPV6_POOL="fd00:abcd::1000-fd00:abcd::2000"

# Verificar root
if [ "$(id -u)" != "0" ]; then
    echo "Ejecuta este script como root."
    exit 1
fi

# Instalar dependencias
install_deps() {
    apt update
    apt install -y libreswan xl2tpd ppp net-tools
}

# Configurar IPsec
setup_ipsec() {
    cat > /etc/ipsec.conf <<EOF
config setup
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12,%v6:fd00::/8
    protostack=netkey

conn l2tp-psk
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    ikelifetime=8h
    keylife=1h
    type=transport
    left=%defaultroute
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/1701
    dpddelay=40
    dpdtimeout=130
    dpdaction=clear
EOF

    echo "%any %any : PSK \"$IPSEC_SECRET\"" > /etc/ipsec.d/l2tp.secret
    chmod 600 /etc/ipsec.d/l2tp.secret
}

# Configurar L2TP y PPP
setup_l2tp() {
    cat > /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes

[lns default]
local ip = 10.0.2.1
ip range = $IPV4_POOL
ipv6 range = $IPV6_POOL
require chap = yes
refuse pap = no
require authentication = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

    cat > /etc/ppp/options.xl2tpd <<EOF
ipcp-accept-local
ipcp-accept-remote
ms-dns $DNS_SERVERS
+ipv6
ipv6cp-accept-local
ipv6cp-use-persistent
logfile /var/log/ppp.log
mtu 1280
mru 1280
auth
proxyarp
nodefaultroute
debug
EOF
}

# Habilitar forwarding
enable_forwarding() {
    sed -i '/net.ipv4.ip_forward/s/^#//g' /etc/sysctl.conf
    sed -i '/net.ipv6.conf.all.forwarding/s/^#//g' /etc/sysctl.conf
    sysctl -p
}

# Menú de gestión de usuarios
user_menu() {
    while true; do
        clear
        echo "=== Gestión de usuarios L2TP ==="
        echo "1) Añadir usuario"
        echo "2) Eliminar usuario"
        echo "3) Listar usuarios"
        echo "4) Salir"
        read -p "Opción: " opt

        case $opt in
            1)
                read -p "Usuario: " user
                read -p "Contraseña: " pass
                read -p "Método (pap/chap/mschap-v1/mschap-v2): " method
                
                case $method in
                    pap) auth="PAP" ;;
                    chap) auth="CHAP" ;;
                    mschap-v1) auth="MS-CHAP-v1" ;;
                    mschap-v2) auth="MS-CHAP-v2" ;;
                    *) echo "Método inválido"; continue ;;
                esac
                
                echo "$user * $pass *" >> /etc/ppp/chap-secrets
                sed -i "/^#/! s/^\(auth.*\)/\1 $auth/" /etc/ppp/options.xl2tpd
                systemctl restart xl2tpd
                echo "Usuario $user añadido con método $auth"
                ;;
            2)
                read -p "Usuario a eliminar: " user
                sed -i "/^$user /d" /etc/ppp/chap-secrets
                echo "Usuario $user eliminado"
                ;;
            3)
                echo "Usuarios configurados:"
                cat /etc/ppp/chap-secrets | grep -v "^#"
                ;;
            4)
                exit 0
                ;;
            *)
                echo "Opción inválida"
                ;;
        esac
        read -p "Presiona Enter para continuar..."
    done
}

# Instalación completa
full_install() {
    install_deps
    setup_ipsec
    setup_l2tp
    enable_forwarding
    systemctl restart ipsec xl2tpd
    systemctl enable ipsec xl2tpd
}

# Menú principal
case "$1" in
    install)
        full_install
        ;;
    manage)
        user_menu
        ;;
    *)
        echo "Uso: $0 [install|manage]"
        exit 1
        ;;
esac
