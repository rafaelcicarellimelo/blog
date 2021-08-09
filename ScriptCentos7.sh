#!/bin/bash

echo "#################################################"
echo "###         INSTALACAO SNEP CENTOS 7          ###"
echo "     SCRIPT MODIFICADO POR RAFAEL CICARELLI      "
echo "          PARA O GRUPO SOLUTIONS                 "
echo "#################################################"
echo -e "\a"
echo -e "\a"
echo -e "\a"
echo -e "\a"

ROOTMYSQL=sneppass

yum update -y

yum remove -y python-paramiko

echo "### Instalando pacotes de desenvolvimento do Kernel"
yum -y install kernel kernel-devel kernel-headers

echo "## Desativando SElinux"
sed -i "s/SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config

while true
do
echo -n "Houve upgrade de kernel? (s ou n) :"
read CONFIRM
case $CONFIRM in
n|N|nao|NAO|Nao) break;;
s|S|SIM|sim|Sim)
echo Abortando instalacao, reiniciando o servidor.
shutdown -r 0
exit
;;
*) echo Por favor, digite somente y ou n
esac
done
echo Voce escolheu $CONFIRM. Continuando ...


echo "### Instalando dependencias do Asterisk / Snep"
rpm -Uhv http://pkgs.repoforge.org/rpmforge-release/rpmforge-release-0.5.3-1.el6.rf.`uname -m`.rpm
yum -y install perl perl-libwww-perl sox cpan bzip2 mpg123
yum -y install mpg123 perl-Crypt-SSLeay perl-IO-Socket-SSL
yum -y install git gcc vim jansson-devel libusb libusb-devel jansson libuuid-devel libuuid sqlite-devel git sqlite cpp bison ncurses ncurses-devel python-devel subversion make\
 ncurses-devel gcc-c++ libxml2-devel unixODBC mysql-connector-odbc dialog mariadb.x86_64 mariadb-server mariadb-devel.x86_64 php-pdo php-pear php php-cli php-cgi\
 php-gd php-mbstring php-mysql php-ncurses php-pear gcc ntpdate ntp unixODBC-devel libtool-ltdl libtool-ltdl-devel dejavu-lgc-fonts bitstream subversion unzip\
 automake wget python-twisted*
yum -y install json.so
yum -y install iptables-service
yum -y install libss7* libopen*
echo "extension=json.so" > /etc/php.d/json.ini

echo "Ajustando a Hora"
ntpdate pool.ntp.org pool.ntp.org pool.ntp.org

echo "### Ativando servicos http e mysql"
service httpd start
service mariadb start

mysqladmin -u root password sneppass

echo "### Desativando servicos desnecessarios e ativando httpd e mysqld no boot"
chkconfig httpd on
chkconfig mariadb on
chkconfig ntpd on
chkconfig iptables off
chkconfig ip6tables off
chkconfig firewalld off

service iptables stop

echo "### Baixando Fontes do Asterisk e DAHDI 2.5 com oslec"
mkdir /usr/src/asterisk
cd /usr/src/asterisk

echo "### Instalando DAHDI 2.4 com suporte a Oslec"
rm -rf dahdi*.tar.gz
wget http://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/dahdi-linux-complete-current.tar.gz
tar zxf dahdi-*.tar.gz
rm -rf dahdi-linux-complete-current.tar.gz
cd dahdi-linux-complete-*
make
make install
make config


cat > /etc/init.d/dahdi << \EOF
#!/bin/sh
#
# dahdi         This shell script takes care of loading and unloading \
#               DAHDI Telephony interfaces
# chkconfig: 2345 9 92
# description: The DAHDI drivers allow you to use your linux \
# computer to accept incoming data and voice interfaces
#
# config: /etc/dahdi/init.conf
### BEGIN INIT INFO
# Provides:        dahdi
# Required-Start:  $local_fs $remote_fs
# Required-Stop:   $local_fs $remote_fs
# Should-Start:    $network $syslog
# Should-Stop:     $network $syslog
# Default-Start:   2 3 4 5
# Default-Stop:    0 1 6
# Short-Description: DAHDI kernel modules
# Description:     dahdi - load and configure DAHDI modules
### END INIT INFO
initdir=/etc/init.d
# Don't edit the following values. Edit /etc/dahdi/init.conf instead.
DAHDI_CFG=/usr/sbin/dahdi_cfg
DAHDI_CFG_CMD=${DAHDI_CFG_CMD:-"$DAHDI_CFG"} # e.g: for a custom system.conf location
FXOTUNE=/usr/sbin/fxotune
# The default syncer Astribank. Usually set automatically to a sane
# value by xpp_sync(1) if you have an Astribank. You can set this to an
# explicit Astribank (e.g: 01).
XPP_SYNC=auto
# The maximal timeout (seconds) to wait for udevd to finish generating
# device nodes after the modules have loaded and before running dahdi_cfg.
DAHDI_DEV_TIMEOUT=20
# A list of modules to unload when stopping.
# All of their dependencies will be unloaded as well.
DAHDI_UNLOAD_MODULES="dahdi"
#
# Determine which kind of configuration we're using
#
system=redhat  # assume redhat
if [ -f /etc/debian_version ]; then
    system=debian
fi
if [ -f /etc/gentoo-release ]; then
    system=debian
fi
if [ -f /etc/SuSE-release -o -f /etc/novell-release ]
then
    system=debian
fi
# Source function library.
if [ $system = redhat ]; then
    . $initdir/functions || exit 0
fi
DAHDI_MODULES_FILE="/etc/dahdi/modules"
[ -r /etc/dahdi/init.conf ] && . /etc/dahdi/init.conf
if [ $system = redhat ]; then
        LOCKFILE=/var/lock/subsys/dahdi
fi
# recursively unload a module and its dependencies, if possible.
# where's modprobe -r when you need it?
# inputs: module to unload.
# returns: the result from
unload_module() {
        module="$1"
        line=`lsmod 2>/dev/null | grep "^$1 "`
        if [ "$line" = '' ]; then return; fi # module was not loaded
        set -- $line
        # $1: the original module, $2: size, $3: refcount, $4: deps list
        mods=`echo $4 | tr , ' '`
        ec_modules=""
        # xpp_usb keeps the xpds below busy if an xpp hardware is
        # connected. Hence must be removed before them:
        case "$module" in xpd_*) mods="xpp_usb $mods";; esac
        for mod in $mods; do
                case "$mod" in
                dahdi_echocan_*)
                        ec_modules="$mod $ec_modules"
                        ;;
                *)
                        # run in a subshell, so it won't step over our vars:
                        (unload_module $mod)
                        ;;
                esac
        done
        # Now that all the other dependencies are unloaded, we can unload the
        # dahdi_echocan modules.  The drivers that register spans may keep
        # references on the echocan modules before they are unloaded.
        for mod in $ec_modules; do
                (unload_module $mod)
        done
        rmmod $module
}
unload_modules() {
        for module in $DAHDI_UNLOAD_MODULES; do
                unload_module $module
        done
}
# In (xpp) hotplug mode, the init script is also executed from the
# hotplug hook. In that case it should not attempt to loade modules.
#
# This function only retunrs false (1) if we're in hotplug mode and
# coming from the hotplug hook script.
hotplug_should_load_modules() {
        if [ "$XPP_HOTPLUG_DAHDI" = yes -a "$CALLED_FROM_ATRIBANK_HOOK" != '' ]
        then
                return 1
        fi
        return 0
}
# In (xpp) hotplug mode: quit after we loaded modules.
#
# In hotplug mode, the main run should end here, whereas the rest of the
# script should be finished by the instance running from the hook.
# Note that we only get here if there are actually Astribanks on the
# system (otherwise noone will trigger the run of the hotplug hook
# script).
hotplug_exit_after_load() {
        if [ "$XPP_HOTPLUG_DAHDI" = yes -a "$CALLED_FROM_ATRIBANK_HOOK" = '' ]
        then
                exit 0
        fi
}
# Initialize the Xorcom Astribank (xpp/) using perl utiliites:
xpp_startup() {
        if [ "$ASTERISK_SUPPORTS_DAHDI_HOTPLUG" = yes ]; then
                aas_param='/sys/module/dahdi/parameters/auto_assign_spans'
                aas=`cat "$aas_param" 2>/dev/null`
                if [ "$aas" = 0 ]; then
                        echo 1>&2 "Don't wait for Astribanks (use Asterisk hotplug-support)"
                        return 0
                fi
        fi
        # do nothing if there are no astribank devices:
        if ! /usr/share/dahdi/waitfor_xpds; then return 0; fi
        hotplug_exit_after_load
}
hpec_start() {
        # HPEC license found
        if ! echo /var/lib/digium/licenses/HPEC-*.lic | grep -v '\*' | grep -q .; then
                return
        fi
        # dahdihpec_enable not installed in /usr/sbin
        if [ ! -f /usr/sbin/dahdihpec_enable ]; then
                echo -n "Running dahdihpec_enable: Failed"
                echo -n "."
                echo "  The dahdihpec_enable binary is not installed in /usr/sbin."
                return
        fi
        # dahdihpec_enable not set executable
        if [ ! -x /usr/sbin/dahdihpec_enable ]; then
                echo -n "Running dahdihpec_enable: Failed"
                echo -n "."
                echo "  /usr/sbin/dahdihpec_enable is not set as executable."
                return
        fi
        # dahdihpec_enable properly installed
        if [ $system = debian ]; then
                echo -n "Running dahdihpec_enable: "
                /usr/sbin/dahdihpec_enable 2> /dev/null
        elif [ $system = redhat ]; then
                action "Running dahdihpec_enable: " /usr/sbin/dahdihpec_enable
        fi
        if [ $? = 0 ]; then
                echo -n "done"
                echo "."
        else
                echo -n "Failed"
                echo -n "."
                echo "  This can be caused if you had already run dahdihpec_enable, or if your HPEC license is no longer valid."
        fi
}
shutdown_dynamic() {
        if ! grep -q ' DYN/' /proc/dahdi/* 2>/dev/null; then return; fi
        # we should only get here if we have dynamic spans. Right?
        $DAHDI_CFG_CMD -s
}
load_modules() {
        # Some systems, e.g. Debian Lenny, add here -b, which will break
        # loading of modules blacklisted in modprobe.d/*
        unset MODPROBE_OPTIONS
        modules=`sed -e 's/#.*$//' $DAHDI_MODULES_FILE 2>/dev/null`
        #if [ "$modules" = '' ]; then
                # what?
        #fi
        echo "Loading DAHDI hardware modules:"
        modprobe dahdi
        for line in $modules; do
                if [ $system = debian ]; then
                        echo -n "   ${line}: "
                        if modprobe $line 2> /dev/null; then
                                echo -n "done"
                        else
                                echo -n "error"
                        fi
                elif [ $system = redhat ]; then
                        action "  ${line}: " modprobe $line
                fi
        done
        echo ""
}
# Make sure that either dahdi is loaded or modprobe-able
dahdi_modules_loadable() {
        modinfo dahdi >/dev/null 2>&1 || lsmod | grep -q -w ^dahdi
}
if [ ! -x "$DAHDI_CFG" ]; then
       echo "dahdi_cfg not executable"
       exit 0
fi
RETVAL=0
# See how we were called.
case "$1" in
  start)
        if ! dahdi_modules_loadable; then
                echo "No DAHDI modules on the system. Not starting"
                exit 0
        fi
        if hotplug_should_load_modules; then
                load_modules
        fi
        TMOUT=$DAHDI_DEV_TIMEOUT # max secs to wait
        while [ ! -d /dev/dahdi ] ; do
                sleep 1
                TMOUT=`expr $TMOUT - 1`
                if [ $TMOUT -eq 0 ] ; then
                        echo "Error: missing /dev/dahdi!"
                        exit 1
                fi
        done
        xpp_startup
        # Assign all spans that weren't handled via udev + /etc/dahdi/assigned-spans.conf
        /usr/share/dahdi/dahdi_auto_assign_compat
        if [ $system = debian ]; then
            echo -n "Running dahdi_cfg: "
            $DAHDI_CFG_CMD 2> /dev/null && echo -n "done"
            echo "."
        elif [ $system = redhat ]; then
            action "Running dahdi_cfg: " $DAHDI_CFG_CMD
        fi
        RETVAL=$?
        if [ "$LOCKFILE" != '' ]; then
                [ $RETVAL -eq 0 ] && touch $LOCKFILE
        fi
        if [ -x "$FXOTUNE" ] && [ -r /etc/fxotune.conf ]; then
                # Allowed to fail if e.g. Asterisk already uses channels:
                $FXOTUNE -s || :
        fi
        # Do not try to call xpp_sync if there are no Astribank devices
        # installed.
        if test -e /sys/bus/astribanks; then
                # Set the right Astribanks ticker:
                LC_ALL=C xpp_sync "$XPP_SYNC"
        fi
        hpec_start
        ;;
  stop)
        # Unload drivers
        #shutdown_dynamic # FIXME: needs test from someone with dynamic spans
        echo -n "Unloading DAHDI hardware modules: "
        if unload_modules; then
                echo "done"
        else
                echo "error"
        fi
        if [ "$LOCKFILE" != '' ]; then
                [ $RETVAL -eq 0 ] && rm -f $LOCKFILE
        fi
        ;;
  unload)
        unload_modules
        ;;
  restart|force-reload)
        $0 stop
        $0 start
        ;;
  reload)
        if [ $system = debian ]; then
            echo -n "Rerunning dahdi_cfg: "
            $DAHDI_CFG_CMD 2> /dev/null && echo -n "done"
            echo "."
        elif [ $system = redhat ]; then
            action "Rerunning dahdi_cfg: " $DAHDI_CFG_CMD
        fi
        RETVAL=$?
        ;;
  status)
        if [ -d /proc/dahdi ]; then
                /usr/sbin/lsdahdi
                RETVAL=0
        else
                RETVAL=3
        fi
        ;;
  *)
        echo "Usage: dahdi {start|stop|restart|status|reload|unload}"
        exit 1
esac
exit $RETVAL
EOF

chmod +x /etc/init.d/dahdi
dahdi_genconf
chkconfig dahdi on
service dahdi start

echo "### Instalando Asterisk"
cd /usr/src/asterisk
rm -rf asterisk-*
wget http://downloads.asterisk.org/pub/telephony/asterisk/asterisk-13-current.tar.gz
tar xzf asterisk-13-current.tar.gz
cd asterisk-13*
./configure
make menuselect.makeopts
menuselect/menuselect --enable res_config_mysql --enable app_mysql --enable app_meetme --enable cdr_mysql --enable EXTRA-SOUNDS-EN-GSM
make
make install
make samples
make config

chkconfig asterisk on

echo "### Ativando Codec g729 free"
cd /usr/lib/asterisk/modules
wget http://asterisk.hosting.lv/bin/codec_g729-ast130-gcc4-glibc-x86_64-barcelona.so -O codec_g729.so

echo "###################################"
echo "### Baixando o snep em /var/www ###"
echo "###################################"

cd /var/www/
git clone https://solutionsvoip@bitbucket.org/snepdev/snep-3.git
mv snep-3 snep
find . -type f -exec chmod 640 {} \; -exec chown apache:apache {} \;
find . -type d -exec chmod 755 {} \; -exec chown apache:apache {} \;
chmod +x /var/www/html/snep/agi/*
cd snep

echo "### Setando permissoes nos logs e arquivos temporarios"
chmod 777 -R /var/www/snep
mkdir /var/log/snep
chmod 777 /var/log/snep

yes | cp -rf /var/www/snep/install/etc/asterisk/* /etc/asterisk/

touch /etc/asterisk/snep/snep-dahdi.conf
touch /etc/asterisk/snep/snep-dahdi-trunk.conf
touch /etc/asterisk/snep/snep-hints.conf

echo "### Fazendo link do snep para o html"
ln -s /var/www/snep/ /var/www/html/snep

ln -s /var/www/snep/agi/ /var/lib/asterisk/agi-bin/snep

sed -i "s/register_globals\ =\ Off/register_globals\ =\ On/g" /etc/php.ini
sed -i "s/register_long_arrays\ =\ Off/register_long_arrays\ =\ On/g" /etc/php.ini
sed -i "s/register_argc_argv\ =\ Off/register_argc_argv\ =\ On/g" /etc/php.ini

service httpd restart

chown -R apache.apache /var/www/snep
chmod -R 777 /etc/asterisk

ln -s /var/lib/asterisk/sounds /var/www/snep/sounds
mkdir /var/www/snep/sounds/moh
chown -R apache.apache *

chmod -R 777 /var/lib/asterisk
chmod -R 777 /etc/asterisk

mkdir /var/www/snep/sounds/pt_BR
chmod -R 777 /var/www/snep

cd /var/www/html/snep/install/database
mysql -u root -psneppass < database.sql
mysql -u root -psneppass snep < schema.sql
mysql -u root -psneppass snep < system_data.sql
mysql -u root -psneppass snep < core-cnl.sql

mysql -u snep -psneppass snep < /var/www/html/snep/install/database/update/3.01/update.sql
mysql -u snep -psneppass snep < /var/www/html/snep/install/database/update/3.06.1/update.sql
mysql -u snep -psneppass snep < /var/www/html/snep/modules/loguser/install/schema.sql


mkdir /var/log/snep
cd /var/log/snep
touch agi.log
ln -s /var/log/asterisk/full full
chown -R apache.apache /var/log/snep
cd /var/www/html/snep/
ln -s /var/log/snep logs
cd /var/lib/asterisk/agi-bin/
ln -s /var/www/html/snep/agi/ snep
cd /var/spool/asterisk/
rm -rf monitor
ln -sf /var/www/html/snep/arquivos monitor

rm -rf /etc/odbc*
cp -avr /var/www/html/snep/install/etc/odbc* /etc/

echo "
[MySQL-snep]
Description     = MySQL ODBC Driver
Driver          = /usr/lib64/libmyodbc5.so
Socket          = /var/lib/mysql/mysql.sock
Server          = localhost
User            = snep
Password        = sneppass
Database        = snep
Option          = 3
" > /etc/odbc.ini

mkdir -p /var/lib/asterisk/moh/tmp /var/lib/asterisk/moh/backup
echo "#################################################"
echo "### SNEP e Asterisk configurados corretamente ###"
echo "#################################################"

echo "###            INICIANDO ASTERISK             ###"

/usr/sbin/asterisk

echo "#################################################"
echo "###             INSTALANDO MONAST             ###"
echo "#################################################"

#apt-get install git php-pear python-dev python-twisted -y

pear upgrade --force --alldeps http://pear.php.net/get/PEAR-1.10.1
pear clear-cache
pear update-channels
pear upgrade
pear upgrade-all

pear install HTTP_Client

cd /usr/src/

wget https://razaoinfo.dl.sourceforge.net/project/starpy/starpy/1.0.0a13/starpy-1.0.0a13.tar.gz
tar zxf starpy-1.0.0a13.tar.gz
cd starpy-1.0.0a13
python setup.py install

cd /usr/src/
wget http://twistedmatrix.com/Releases/Twisted/12.0/Twisted-12.0.0.tar.bz2
tar -xf Twisted-12.0.0.tar.bz2
cd Twisted-12.0.0
python setup.py install

mkdir /var/www/html/painel ; cd /var/www/html/painel
git clone https://github.com/dagmoller/monast.git .

echo "" >> /etc/asterisk/manager.conf
echo "[monast]" >> /etc/asterisk/manager.conf
echo "secret = monast" >> /etc/asterisk/manager.conf
echo "deny=0.0.0.0/0.0.0.0" >> /etc/asterisk/manager.conf
echo "permit=0.0.0.0/0.0.0.0" >> /etc/asterisk/manager.conf
echo "read = all" >> /etc/asterisk/manager.conf
echo "write = all" >> /etc/asterisk/manager.conf

asterisk -rx "reload manager"

echo "/var/www/html/painel/pymon/monast.py --daemon" >> /etc/rc.local

cp /var/www/html/painel/pymon/monast.conf.sample /etc/monast.conf

sed -i 's/Server_1/Asterisk/g' /etc/monast.conf
sed -i 's/192.168.0.1/127.0.0.1/g' /etc/monast.conf
sed -i 's/ami_username/monast/g' /etc/monast.conf
sed -i 's/ami_password/monast/g' /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf
sed -i 60d /etc/monast.conf

/var/www/html/painel/pymon/monast.py --daemon

echo "#################################################"
echo "###           INSTALANDO SONS PT_BR           ###"
echo "#################################################"

cd /var/lib/asterisk/
mv sounds sounds-old
wget www.syssvoip.com.br/asterisk/sounds.tar.gz
tar -zxf sounds.tar.gz
chmod 777 -R sounds

mkdir /var/lib/asterisk/sounds/backup
mkdir /var/lib/asterisk/sounds/tmp

mkdir /var/lib/asterisk/sounds/pt_BR/tmp

rm -rf /var/www/snep/sounds
ln -s /var/lib/asterisk/sounds /var/www/snep/sounds
chown -R apache.apache /var/www/snep/sounds
chown -R apache.apache /var/lib/asterisk/sounds

cd /var/lib/asterisk/moh
chown -R apache.apache *
chown apache:apache /var/lib/asterisk/moh

cd /var/www/html/snep/sounds
ln -sf /var/lib/asterisk/moh/ moh

cd /var/www/html/snep/install
mv index.html /var/www/html/

mkdir /root/.ssh/
chmod 0700 /root/.ssh/
echo "
ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQBZ7Ho0E0CnPaloXByQPIH5P16r93YADrpRHl9YwybNRrJr7QaS1gIDlRlTysHbphjnyDkN6zqojcoaY8MT/TwoW/22Z6tjBvZ8+SJBpdv5sacnXbOlavDFPFABu5zJg12Gr/RlVHRM2c7oTlFQKxtQ1aaJO0ESuD3sX9RkWBo9mW2nMZBbdr/mgjELxX82hXVB00XNxZJUO9RKDognMy/dY7uwCD8uIAjRqV38j6SeNYA2pNm1nvqsTcAbidGvKfv3C8u2lCoDF3ItdmF8HYHddP2NX5yiR2HxA8bKdBtvdaK0hvU94gcygb3BHekRUKURJR6H2vueGSOJI7DH6G0/ rsa-key-20190709
ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEA3O1u37007MSHewH75etIruAA4bWqH8RDGUvkBYpN64Gq/3N20X7/28Y72ss3xL6JEI/WjqOWSncfqlPCHiPO42740ltTi7zOhT24pdpmfLdAoaHXG9HhDTd1LZ+UZOycKyglTr2FCOGd1+ekvVe//EW5O/yddGobrClcT25gyldCFUIlQ6crjWoW0wtKW9jJcUb6ZvA/OxkcTUNvghCbaKBHvqBOasRZQvbQo1pfAnfLBqIvq4Ve++3P8mXi2UI6Jy340dpm41KUGfrRVSLrZ6yUQnwrryRbsw+p4TyVo+G6J69fNN9upRMuaA3JvXfWLormllYqG6O4kdsJSpeJDQ== rsa-key-20200807
ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEA3+GVEy8G3qoEb+AnmFl5WjqYiCi8Kx3Aq2s81fOhz8F0m9dvR8cUr6QfDGKuU+Z7De61djRxXOmgVqFdPgPbKSv7z6IckZLD2uZPKLrYoNT9ez3WEIbsMxkXygjaWZEh+oVC2YlQBFsAZSuQi09v1+6zaEALmEdrJrP0RiAiGpJvIXqCD/ZDImILFI4UqwNs67f43z/wNfHAZycJtyF+OWN1Nnnk3By9J4BXYejFQ4CQwrW1IfCOLj14rS6aF9kGjoK2sAa4h4A9o+Pa6a710kTxxoNPulZ+1e8IVVdV4VVYBf1ZdiG4xFtnNOnXAV9j3N0si7rtqzLPDZWIgHwT6Q== rsa-key-20200818
ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAuLc3T5xRiQWmd6pVktMzz2nzY090UUl55FZvbNWH451RLruQgLEjftxxJJc/cR9Nl61SnbLv6gtME7Me+mHasi46sMtqcNxTn+0m2ylPD+5KedpwltGSnFlUB4UtIWi/2/sguEtVibxltss6IQPYOrwYwi5anTGsZPYsOZw1fDCvHwznWBtNylhIvMPZwr+6/CeZMEXsaulqgGCpRzZ1J88Su0z1suW02o+31ceojL+yxDF8mv4EaNIZKIGVtiiBqFcb41EIeK0COtl8ypk4/g3w0/pAl17Sj16BKZIZ+R7ZtyUVfWE0mKnS4d75cx9BgULBtaezEy8RdVDC8WTmNQ== rsa-key-20200818
ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAlNTpaz/QiarjVgRUlFsAqA6NzneabEp3BZkQpTTZ2jvgqQglg+/E5fkxOzoGs92j2TPNYeBEZvNaxLnxrAVmSmHBtBgxu54krakGrGduqugWfUa1yUUkDqr01Ix9WREJ7R0KViUpHhJ00dCloKmKImDt84Pz+F+HHmz0tclW0j47ms4645atURyahsfhS9C3v6jktOyTia+QZLLVTkd/PPpZMBx9tYt9ISM53qxzhi32zU1LCT7P/ZO4jCtiIJi3LwOLeLtwWxKS7RDUhCIP/ZgH37N8XGZiqI6zBV+7MDKHgTxOkfc3N2kd81cMsJpEl3QsX6S4I8WWhiwxlJhFXw== rsa-key-20201026
ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAQEAup+rPjzRFHlljoFhFq/lXjFJfcHKGl95d8jYbcap9d/JI3D72FIBQ5R0qd2UmBykoPwFh3LHnNTAHMMegAgbphPx1BtdjIL7TVsRi1U/wDj93Elo2zMar4ZY63VguXs2jkTHfVpSczKg38Ya54oWiOVA0uRb15MoKZU6omvGlnc5VsdoaJbVpsFim4J0TnA/+zl52AR+ZlW3/SuxWoPzqQpG4wkaedu4rL8ftqH9I6N55ReoWTY+Ns61DWAIREuZU7o1iNY63mAyQpK1JBbJssQ1pobY3lc/xDXHTKMPCgdN7UXQfkHYs0lfUo1X7fG9TmytyW2TkfyVi2aG7JGaYQ== rsa-key-20201105
" > /root/.ssh/authorized_keys

echo "########## Q-Manager ########"
yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum-config-manager --enable docker-ce-edge

yum install docker-ce -y

service docker start

wget -qO inst.sh http://ocl.opens.com.br/docker/install.sh && chmod +x inst.sh && ./inst.sh

echo
echo "Fail2ban configuration!"
echo

cd /usr/src
rm -rf /etc/fail2ban/
wget https://downloads.sourceforge.net/project/fail2ban/fail2ban-stable/fail2ban-0.8.11/fail2ban-0.8.11.tar.gz
tar xzvf fail2ban-0.8.11.tar.gz
cd fail2ban-0.8.11
python setup.py install

cp -rf files/redhat-initd /etc/init.d/fail2ban
cd /etc/fail2ban/filter.d


cat > /etc/fail2ban/filter.d/asterisk.conf << \EOF
[INCLUDES]
before = common.conf
 
[Definition]
log_prefix= \[\]\s*(?:NOTICE|SECURITY)%(__pid_re)s:?(?:\[\S+\d*\])? \S+:\d*
 
failregex = ^%(log_prefix)s Registration from '[^']*' failed for '<HOST>(:\d+)?' - Wrong password$
            ^%(log_prefix)s Registration from '[^']*' failed for '<HOST>(:\d+)?' - No matching peer found$
            ^%(log_prefix)s Registration from '[^']*' failed for '<HOST>(:\d+)?' - Username/auth name mismatch$
            ^%(log_prefix)s Registration from '[^']*' failed for '<HOST>(:\d+)?' - Device does not match ACL$
            ^%(log_prefix)s Registration from '[^']*' failed for '<HOST>(:\d+)?' - Peer is not supposed to register$
            ^%(log_prefix)s Registration from '[^']*' failed for '<HOST>(:\d+)?' - ACL error \(permit/deny\)$
            ^%(log_prefix)s Registration from '[^']*' failed for '<HOST>(:\d+)?' - Not a local domain$
            ^%(log_prefix)s Call from '[^']*' \(<HOST>:\d+\) to extension '\d+' rejected because extension not found in context 'default'\.$
            ^%(log_prefix)s Host <HOST> failed to authenticate as '[^']*'$
            ^%(log_prefix)s No registration for peer '[^']*' \(from <HOST>\)$
            ^%(log_prefix)s Host <HOST> failed MD5 authentication for '[^']*' \([^)]+\)$
            ^%(log_prefix)s Failed to authenticate (user|device) [^@]+@<HOST>\S*$
            ^%(log_prefix)s (?:handle_request_subscribe: )?Sending fake auth rejection for (device|user) \d*<sip:[^@]+@<HOST>>;tag=\w+\S*$
            ^%(log_prefix)s SecurityEvent="(FailedACL|InvalidAccountID|ChallengeResponseFailed|InvalidPassword)",EventTV="[\d-]+",Severity="[\w]+",Service="[\w]+",EventVersion="\d+",AccountID="\d+",SessionID="0x[\da-f]+",LocalAddress="IPV[46]/(UD|TC)P/[\da-fA-F:.]+/\d+",RemoteAddress="IPV[46]/(UD|TC)P/<HOST>/\d+"(,Challenge="\w+",ReceivedChallenge="\w+")?(,ReceivedHash="[\da-f]+")?$
 
# Option:  ignoreregex
# Notes.:  regex to ignore. If this regex matches, the line is ignored.
# Values:  TEXT
#
ignoreregex =
EOF


echo '
[INCLUDES]
[Definition]
failregex = NOTICE.* .*: Useragent: sipcli.*\[<HOST>\] 
ignoreregex =
' > /etc/fail2ban/filter.d/asterisk_cli.conf

echo '
[INCLUDES]
[Definition]
failregex = .*NOTICE.* <HOST> tried to authenticate with nonexistent user.*
ignoreregex =
' > /etc/fail2ban/filter.d/asterisk_manager.conf

echo '
[INCLUDES]
[Definition]
failregex = NOTICE.* .*hangupcause to DB: 200, \[<HOST>\]
ignoreregex =
' > /etc/fail2ban/filter.d/asterisk_hgc_200.conf

cd /etc/fail2ban/filter.d/
rm -rf /etc/fail2ban/filter.d/sshd.conf
wget http://magnusbilling.com/scriptsSh/sshd.conf

echo "
[DEFAULT]
ignoreip = 127.0.0.1 191.36.173.99 143.255.80.247 
bantime  = 600
findtime  = 600
maxretry = 3
backend = auto
usedns = warn
[asterisk-iptables]   
enabled  = true           
filter   = asterisk       
action   = iptables-allports[name=ASTERISK, port=5060, protocol=all]   
logpath  = /var/log/asterisk/fail2ban 
maxretry = 5  
bantime = 600
[ast-cli-attck]   
enabled  = true           
filter   = asterisk_cli     
action   = iptables-allports[name=AST_CLI_Attack, port=5060, protocol=all]
logpath  = /var/log/asterisk/messages 
maxretry = 1  
bantime = -1
[asterisk-manager]   
enabled  = true           
filter   = asterisk_manager     
action   = iptables-allports[name=AST_MANAGER, port=5038, protocol=all]
logpath  = /var/log/asterisk/messages 
maxretry = 1  
bantime = -1
[ast-hgc-200]
enabled  = true           
filter   = asterisk_hgc_200     
action   = iptables-allports[name=AST_HGC_200, port=5060, protocol=all]
logpath  = /var/log/asterisk/messages
maxretry = 20
bantime = -1
[ssh-iptables]
enabled  = true
filter   = sshd
action   = iptables-allports[name=SSH, port=all, protocol=all]
logpath  = /var/log/secure
maxretry = 3
bantime = 600
" > /etc/fail2ban/jail.conf


echo "
[general]
dateformat=%F %T       ; ISO 8601 date format
[logfiles]
;debug => debug
;security => security
console => warning,error
;console => notice,warning,error,debug
messages => notice,warning,error
;full => notice,warning,error,debug,verbose,dtmf,fax
fail2ban => notice,security
" > /etc/asterisk/logger.conf

asterisk -rx "module reload logger"
chkconfig fail2ban on
service fail2ban restart
iptables -L -v

cd /root

echo "mkdir /var/run/fail2ban" >> /etc/rc.local
echo "/var/www/html/painel/pymon/monast.py --daemon" >> /etc/rc.local

chmod +x /etc/rc.d/rc.local

echo "#################################################"
echo "###           INSTALACAO CONCLUIDA            ###"
echo "  REINICIAR O SERVIDOR PARA APLICAR ALTERACOES   "
echo "#################################################"
echo -e "\a"
echo -e "\a"
echo -e "\a"
echo -e "\a"
