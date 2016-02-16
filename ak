#!/bin/bash

PROGNAME="`basename $0`"
cd config
. ak.conf

die()
{
	m=$1
	echo $m
	exit
}

usage()
{
	echo "OVM quick install:"
	echo "	1. Install packages: $PROGNAME -I"
	echo "	2. Edit config/ak.conf"
	echo "	3. Install configurations: $PROGNAME -i"
	echo "	4. Set IPtables and save: $PROGNAME -S"
	echo "OVM Management:"
	echo "	Backup configurations: $PROGNAME -B"
	echo "	Restore configurations: $PROGNAME -R [ archive.tgz ]"
	echo "OpenVPN Management:"
	echo "	Add users: $PROGNAME <-l list | -u user> [-e days]"
	echo "	Revoke users: $PROGNAME <-r user> [-e days]"
	echo "IPtables Management:"
	echo "	Set IPtables and save: $PROGNAME -S"
	echo "	Set IPtables without save: $PROGNAME -s"
	echo "	Clear IPtables and save: $PROGNAME -C"
	echo "Uninstall OVM:"
	echo "	$PROGNAME <--clean | -c>" 
	exit
}

clean() {
	echo ">>>>>>>>> Cleaning..."
	# Clean certificationns
	if [ -e "$CRT/ca.crt" ]; then
		rm $CRT/*.tar.gz
		rm $CRT/ca.crt
		rm $SERVERPATH/$PORT*
	fi

	# Clean keys
	$KEYMAKER/clean-all

	# Restart openvpn service
	/etc/init.d/openvpn restart

	# Recover pptp, ipsec, l2tp, ppp
	echo "Recovering pptp, ipsec, l2tp..."
	if [ -e "/etc/pptpd.conf~" ]; then
		mv /etc/pptpd.conf~ /etc/pptpd.conf
		mv /etc/ppp/pptpd-options~ /etc/ppp/pptpd-options
		mv /etc/ppp/chap-secrets~ /etc/ppp/chap-secrets
		mv /etc/ipsec.conf~ /etc/ipsec.conf
		mv /etc/ipsec.secrets~ /etc/ipsec.secrets
		mv /etc/xl2tpd/xl2tpd.conf~ /etc/xl2tpd/xl2tpd.conf
		rm /etc/ppp/options.xl2tpd
		echo lesca > $CONFIG/users
	fi 
	if [ -e "/etc/init.d/vpn.init" ]; then
		update-rc.d -f vpn.init remove > /dev/null
		update-rc.d ipsec defaults > /dev/null
		update-rc.d xl2tpd defaults > /dev/null
		rm /etc/init.d/vpn.init
	fi
	echo "Done!"
	exit
}

makekey() {
	username=$1
	echo "=================================================="
	echo "Generating keys for $username ..."
	cd $KEYMAKER
	if ls -1 $KEY_DIR | grep $username; then
	    ./revoke-full $username
	fi

	./pkitool $username

	cd $CRT
	cat "$CLIENTCONF" | sed -e "s/%USRNAME%/$username/g" -e "s/%HOST%/$HOST/g" -e "s/%PORT%/$PORT/g" -e "s/%BUFF%/$BUFF/g" > $CRT/$username.ovpn

	cp $KEY_DIR/$username.crt $CRT
	cp $KEY_DIR/$username.key $CRT
	if [ -e $CRT/$username.tar.gz ]; then
	    tar -czf "$username.tar.gz" "ca.crt" "$username.crt" "$username.key" "$username.ovpn" "3.GUI.ba_"
	else
	    tar -czf "$username.tar.gz" "ca.crt" "$username.crt" "$username.key" "$username.ovpn" "$CLIENT" "1.readme.txt" "3.GUI.ba_"
	fi

	rm "$username.crt" "$username.key" "$username.ovpn"
}

makeca() {
        echo ">>>>>>>>> Initializing...."
        cd $KEYMAKER
        ./clean-all
        ./build-dh
        ./pkitool --initca
        ./pkitool --server server

	# chmod keys
        chown daemon $KEY_DIR/server.key
        chmod +r $KEY_DIR/ca.key
        chmod +rx $KEY_DIR
        cp $KEY_DIR/ca.crt $CRT

        # generate server config
        cat $SERVERCONF | sed -e "s/%PORT%/$PORT/g" -e "s/%KEY_SIZE%/$KEY_SIZE/g" -e "s/%KEY_DIR%/$PORT\/keys/g" -e "s/%SUBNET%/$SUBNET/g" -e "s/%MASK%/$MASK/g" -e "s/%DNS%/$DNS/g" -e "s/%BUFF%/$BUFF/g" -e "s/%BIN%/$PORT\/bin/g" > "$SERVERPATH/$PORT.conf"
	if [ ! -e $SERVERPATH/$PORT ]; then
		ln -s $VPN $SERVERPATH/$PORT
	fi

        # restart openvpn service; rollback if failed
        /etc/init.d/openvpn restart || clean

        # load user list
        [ -e "$CONFIG/users" ] && list="$CONFIG/users"

	# prepare pem
        makekey root
        revoke root
}

revoke() {
    if [ -e "$CRT/$1.tar.gz" ]; then
	cd $KEYMAKER
	./revoke-full $1
	rm "$CRT/$1.tar.gz"
	echo "DONE!"
    else 
	echo "Error: No such user!"
    fi
}

iptables-clean() {
	# Clean iptables rules
        iptables -t nat -F
        iptables -F

	if [ -e "/etc/$RULES" ]; then
		rm /etc/$RULES
	fi

        echo "iptables cleaned!"
}

iptables-set() {
if [ "$RULELOADER" = "" ]; then
	$BIN/iptables.default
	echo "Warning: iptables load default!"
else
	$BIN/$RULELOADER
fi

	iptables-save

if [ "$1" = "-S" ]; then
	iptables-save > /etc/$RULES
	echo "iptables saved!"
else
        echo "iptables loaded!"
fi
}

addkey() {
cd $KEYMAKER

if [ ! -e "$CRT/ca.crt" ]; then
    makeca
fi

# Set expire date
[ "$expire" ] && export KEY_EXPIRE=$expire

# Generate keys
if [ "$1" ]; then
        makekey $1
fi

if [ -e "$list" ]; then
    cat "$list" | while read line; do
        username=${line%@*}
        makekey $username
    done
fi

}

Install() {
CR=`lsb_release -r | cut -f2 | cut -c1-2`
if [ $CR -lt "12" ]; then
    apt-get install python-software-properties
    add-apt-repository ppa:openswan/ppa
fi

# log
    if [ ! -e "/var/log/vpn" ]; then
        mkdir /var/log/vpn
        chown daemon /var/log/vpn
    fi

    apt-get update
    apt-get install openvpn openssl openswan xl2tpd pptpd
    echo "Then ..."
    echo "1. Edit config/ak.conf"
    echo "2. ak -i"
    echo "3. ak -S"
    echo "Done!"
}

setup() {
    if [ "$HOST" = "" ]; then
        die "Error: HOST is empty!!"
    fi
# pptp
    if [ ! -e "/etc/pptpd.conf~" ]; then
        cp /etc/pptpd.conf /etc/pptpd.conf~
    fi
    cp $CONFIG/pptpd.conf /etc/pptpd.conf
    if [ ! -e "/etc/ppp/pptpd-options~" ]; then
        cp /etc/ppp/pptpd-options /etc/ppp/pptpd-options~
    fi
    cat $CONFIG/pptpd-options | sed "s/%DNS%/$DNS/g" > /etc/ppp/pptpd-options
# ipsec
    if [ ! -e "/etc/ipsec.conf~" ]; then
        cp /etc/ipsec.conf /etc/ipsec.conf~
    fi
    cat $CONFIG/ipsec.conf | sed "s/%LOCALIP%/$LOCALIP/g" | sed "s/%GATEWAY%/$GATEWAY/g" > /etc/ipsec.conf
    if [ ! -e "/etc/ipsec.secrets~" ];then
        cp /etc/ipsec.secrets /etc/ipsec.secrets~
    fi
    cat $CONFIG/ipsec.secrets | sed "s/%LOCALIP%/$LOCALIP/g" > /etc/ipsec.secrets
# xl2tp
    if [ ! -e "/etc/xl2tpd/xl2tpd.conf~" ]; then
        cp /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf~
    fi
    cp $CONFIG/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf
    cat $CONFIG/options.xl2tpd | sed "s/%DNS%/$DNS/g" > /etc/ppp/options.xl2tpd
# ppp
    cp /etc/ppp/chap-secrets /etc/ppp/chap-secrets~
    cp $CONFIG/chap-secrets /etc/ppp/chap-secrets
# openvpn
    addkey

# update init.d links
    if [ ! -e "/etc/init.d/vpn.init" ]; then
        update-rc.d -f ipsec remove > /dev/null
        update-rc.d -f xl2tpd remove > /dev/null
        ln -s $BIN/vpn.init /etc/init.d/vpn.init
        update-rc.d vpn.init defaults > /dev/null
    fi

# Restart services
    $BIN/vpn.init restart

# Prompt
    echo "DONE!"
    echo 'For first setup, run "ak -S" to setup iptables...'
    echo "To config iptables rules, edit $BIN/iptables.customized"
}

backup() {
	cd $VPN
        echo ">>>>>>>>> Backupping..."
	[ -d "$BACKUPDIR" ] || mkdir "$BACKUPDIR"
	acvname=ovmcert.`date +%y%m%d%H%M%S`.tgz

        # Backup certificationns
        if [ -e "$CRT/ca.crt" ]; then
		tar -czvPf $acvname crt keys config/users config/ak.conf bin/iptables.custom $SERVERPATH/$PORT.* /etc/pptpd.conf /etc/ppp/pptpd-options /etc/ppp/chap-secrets /etc/ipsec.conf /etc/ipsec.secrets /etc/xl2tpd/xl2tpd.conf /etc/ppp/options.xl2tpd
		mv $acvname $BACKUPDIR 
        fi

        echo "Done!"
        exit
}

restore() {
	cd $VPN
        echo ">>>>>>>>> Restoring..."

        # Restore check
        if [ -e "$CRT/ca.crt" ]; then
		die "Error: $CRT/ca.crt existed!!"
        fi

	if [ "$1" ]; then
		if [ -e "$1" ]; then
		acvname="$1"
		else
		die "Error: Backup file \"$1\" not found!"
		fi
	else
		if [ -d "$BACKUPDIR" ];then
		acvname=$BACKUPDIR/`ls -t1 $BACKUPDIR | head -n1`
		echo "Use latest backup archive: \"$acvname\""
		else
		die "Error: No backup file found!"
		fi
	fi

	# Restore symbolic link
        if [ ! -e $SERVERPATH/$PORT ]; then
                ln -s $VPN $SERVERPATH/$PORT
	else
		die "Error: Port $PORT has been allocated by another instance."
        fi

	# Backup previous configuration
        cp /etc/pptpd.conf /etc/pptpd.conf~
        cp /etc/xl2tpd/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf~
        cp /etc/ppp/chap-secrets /etc/ppp/chap-secrets~
        cp /etc/ipsec.secrets /etc/ipsec.secrets~
        cp /etc/ipsec.conf /etc/ipsec.conf~
	if [ -e "/etc/ppp/pptpd-options" ]; then
	        cp /etc/ppp/pptpd-options /etc/ppp/pptpd-options~
	fi
	if [ -e "/etc/ppp/options.xl2tpd" ]; then
	        cp /etc/ppp/options.xl2tpd /etc/ppp/options.xl2tpd~
	fi

	# De-archive
	tar -xzvPf $acvname

	# Restore ipsec
        sed -i -e "s/left=\(.*\)/left=$LOCALIP/g" -e " s/leftnexthop=\(.*\)/leftnexthop=$GATEWAY/g" /etc/ipsec.conf
        sed -i "s/\(.*\)%/$LOCALIP %/g" /etc/ipsec.secrets

	# update init.d links
        if [ ! -e "/etc/init.d/vpn.init" ]; then
            update-rc.d -f ipsec remove > /dev/null
            update-rc.d -f xl2tpd remove > /dev/null
            ln -s $BIN/vpn.init /etc/init.d/vpn.init
            update-rc.d vpn.init defaults > /dev/null
        fi

	# Restart services
        $BIN/vpn.init restart

        echo "Done!"
        exit
}

# Read command parameters
while [ $# -gt 0 ]; do
    case "$1" in  
	--expire | -e )
        	expire=$2
        	shift ;;
	--user | -u )
		addkey $2
		exit ;;
	-list | -l )
		list=$2
		shift ;;
	--clean | -c )
		clean ;;
	--revoke | -r )
		revoke $2
		exit ;;
	-i )
		setup $2
		exit ;;
	-I )
		Install	
		exit ;;
	-S )
		iptables-clean
		iptables-set -S
		exit ;;
	-s )
		iptables -F
		iptables -t nat -F
		iptables-set -s
		exit ;;
	-C )
		iptables-clean
		exit ;;
	--backup | -B )
		backup	
		exit ;;
	--restore | -R )
		restore $2
		exit ;;
	--help)
		usage
		exit ;;
    # errors
    --* ) die "$PROGNAME: Unknown option: $1" ;;
    * ) break ;;
    esac
shift
done

# Nothing 
usage
