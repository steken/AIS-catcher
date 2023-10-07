#!/bin/bash

# Contributions to https://github.com/abcd567a/install-aiscatcher

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

echo "Installing build tools and dependencies..."
apt-get update
apt-get install -y git make gcc g++ cmake pkg-config librtlsdr-dev whiptail minify

INSTALL_FOLDER=/usr/share/aiscatcher
echo "Creating folder aiscatcher if it does not exist"
mkdir -p ${INSTALL_FOLDER}

function create-config(){
echo "Creating config file aiscatcher.conf"
CONFIG_FILE=${INSTALL_FOLDER}/aiscatcher.conf
touch ${CONFIG_FILE}
chmod 777 ${CONFIG_FILE}
echo "Writing code to config file aiscatcher.conf"
/bin/cat <<EOM >${CONFIG_FILE}
 -d:0
 -gr TUNER auto RTLAGC on BIASTEE off
 -u 127.0.0.1 10110
 -N 8383 PLUGIN_DIR /usr/share/aiscatcher/my-plugins STATION "Station" SHARE_LOC on LAT 59.000000 LON 17.000000 REALTIME on MSG on
EOM
chmod 644 ${CONFIG_FILE}
}

if [[ -f "${INSTALL_FOLDER}/aiscatcher.conf" ]]; then
   CHOICE=$(whiptail --title "CONFIG" --menu "An existing config file 'aiscatcher.conf' found. What you want to do with it?" 20 60 5 \
   "1" "KEEP existing config file \"aiscatcher.conf\" " \
   "2" "REPLACE existing config file by default config file" 3>&1 1>&2 2>&3);
   if [[ ${CHOICE} == "2" ]]; then
      if (whiptail --title "Confirmation" --yesno "Are you sure you want to REPLACE your existing config file by default config File?" --defaultno 10 60 5 ); then
        echo "Saving old config file as \"aiscatcher.conf.old\" ";
        cp ${INSTALL_FOLDER}/aiscatcher.conf ${INSTALL_FOLDER}/aiscatcher.conf.old;
        create-config
      fi
   fi

elif [[ ! -f "${INSTALL_FOLDER}/aiscatcher.conf" ]]; then
   create-config
fi

echo "Creating startup script file start-ais.sh"
SCRIPT_FILE=${INSTALL_FOLDER}/start-ais.sh
touch ${SCRIPT_FILE}
chmod 777 ${SCRIPT_FILE}
echo "Writing code to startup script file start-ais.sh"
/bin/cat <<EOM >${SCRIPT_FILE}
#!/bin/sh
CONFIG=""
while read -r line; do CONFIG="\${CONFIG} \$line"; done < ${INSTALL_FOLDER}/aiscatcher.conf
cd ${INSTALL_FOLDER}
/usr/local/bin/AIS-catcher \${CONFIG}
EOM
chmod +x ${SCRIPT_FILE}


echo "Creating Service file aiscatcher.service"
SERVICE_FILE=/lib/systemd/system/aiscatcher.service
touch ${SERVICE_FILE}
chmod 777 ${SERVICE_FILE}
/bin/cat <<EOM >${SERVICE_FILE}
# AIS-catcher service for systemd
[Unit]
Description=AIS-catcher
Wants=network.target
After=network.target
[Service]
User=aiscat
RuntimeDirectory=aiscatcher
RuntimeDirectoryMode=0755
ExecStart=/bin/bash ${INSTALL_FOLDER}/start-ais.sh
SyslogIdentifier=aiscatcher
Type=simple
Restart=on-failure
RestartSec=30
RestartPreventExitStatus=64
Nice=-5
[Install]
WantedBy=default.target

EOM

chmod 644 ${SERVICE_FILE}
systemctl enable aiscatcher

echo "Entering install folder..."
cd ${INSTALL_FOLDER}
echo "Removeing old source..."
rm -r AIS-catcher
echo "Cloning source-code of AIS-catcher from Github and making executeable..."
git clone https://github.com/steken/AIS-catcher.git
cd AIS-catcher
git config --global --add safe.directory ${INSTALL_FOLDER}/AIS-catcher
git fetch --all
git reset --hard origin/main
rm -rf build
echo "Bake HTML..."
cd HTML
./bake
echo "Build..."
cd ..
mkdir -p build
cd build
cmake ..
make
echo "Copying AIS-catcher binary in folder /usr/local/bin/ "
if [[ -f "${INSTALL_FOLDER}/AIS-catcher/build/AIS-catcher" ]]; then
   echo "Stoping existing aiscatcher to enable over-write"
   systemctl stop aiscatcher
   killall AIS-catcher
   echo "Copying newly built binary \"AIS-catcher\" to folder \"/usr/local/bin/\" "
   cp ${INSTALL_FOLDER}/AIS-catcher/build/AIS-catcher /usr/local/bin/AIS-catcher

elif [[ ! -f "${INSTALL_FOLDER}/AIS-catcher/build/AIS-catcher" ]]; then
   echo " "
   echo -e "\e[1;31mAIS binary was not built\e[39m"
   echo -e "\e[1;31mPlease run install script again\e[39m"
   exit
fi

if [[ -d "${INSTALL_FOLDER}/my-plugins" ]]; then
   CHOICE=$(whiptail --title "CONFIG" --menu "An existing directory 'my-pugins' found. What you want to do with it?" 20 60 5 \
   "1" "KEEP existing directory \"my-plugins\" " \
   "2" "REPLACE existing directory by all source plugins" 3>&1 1>&2 2>&3);
   if [[ ${CHOICE} == "2" ]]; then
      if (whiptail --title "Confirmation" --yesno "Are you sure you want to REPLACE your existing plugins?" --defaultno 10 60 5 ); then
         echo "Renaming existing folder \"my-plugins\" to \"my-plugins.old\" "
         rm -rf ${INSTALL_FOLDER}/my-plugins.old
         mv ${INSTALL_FOLDER}/my-plugins ${INSTALL_FOLDER}/my-plugins.old
         echo "Copying files from Source code folder \"AIS-catcher/plugins\" to folder \"my-plugins\" "
         mkdir ${INSTALL_FOLDER}/my-plugins
         cp ${INSTALL_FOLDER}/AIS-catcher/plugins/* ${INSTALL_FOLDER}/my-plugins/
      fi
   fi
else
   echo "Copying files from Source code folder \"AIS-catcher/plugins\" to folder \"my-plugins\" "
   mkdir ${INSTALL_FOLDER}/my-plugins
   cp ${INSTALL_FOLDER}/AIS-catcher/plugins/* ${INSTALL_FOLDER}/my-plugins/
fi


echo "Creating User aiscat to run AIS-catcher"
useradd --system aiscat
usermod -a -G plugdev aiscat

echo "Assigning ownership of install folder to user aiscat"
chown aiscat:aiscat -R ${INSTALL_FOLDER}

systemctl start aiscatcher

echo " "
echo " "
echo -e "\e[32mINSTALLATION COMPLETED \e[39m"
echo -e "\e[32m=======================\e[39m"
echo -e "\e[32mPLEASE DO FOLLOWING:\e[39m"
echo -e "\e[32m=======================\e[39m"

echo -e "\e[33m(1) If on RPi you have installed AIS Dispatcher or OpenCPN,\e[39m"
echo -e "\e[33m    it should be configured to use UDP Port 10110, IP 127.0.0.1 OR 0.0.0.0\e[39m"

echo -e "\e[33m(2) Open file aiscatcher.conf by following command:\e[39m"
echo -e "\e[39m       sudo nano "${INSTALL_FOLDER}"/aiscatcher.conf \e[39m"
echo -e "\e[33m(3) In above file:\e[39m"
echo -e "\e[33m    (a) Change 00000162 in \"-d 00000162\" to actual Serial Number of AIS dongle\e[39m"
echo -e "\e[33m    (b) Change 3 in \"-p 3\" to the actual ppm correction figure of dongle\e[39m"
echo -e "\e[33m    (c) Change 38.6 in \"-gr TUNER 38.6 RTLAGC off\" to desired Gain of dongle\e[39m"
echo -e "\e[33m    (d) Add following line and replace xx.xxx and yy.yyy by actual values:\e[39m"
echo -e "\e[35m          -N STATION MyStation LAT xx.xxx LON yy.yyy \e[39m"
echo -e "\e[33m    (e) For each Site you want to feed AIS data, add a new line as follows:\e[39m"
echo -e "\e[35m          -u [URL or IP of Site] [Port Number of Site]  \e[39m"
echo -e "\e[33m    (f) Save (Ctrl+o) and  Close (Ctrl+x) file aiscatcher.conf \e[39m"
echo " "
echo -e "\e[01;31mIMPORTANT: \e[32mIf you are \e[01;31mUpgrading or Reinstalling,\e[32myour old config file & pluin folder are saved as \e[39m"
echo -e "\e[39m       "${INSTALL_FOLDER}/aiscatcher.conf.old" \e[39m"
echo -e "\e[39m       "${INSTALL_FOLDER}/my-plugins.old" \e[39m"
echo " "
echo -e "\e[01;31m(4) REBOOT RPi ... REBOOT RPi ... REBOOT RPi \e[39m"
echo " "
echo -e "\e[01;32m(5) See the Web Interface (Map etc) at\e[39m"
echo -e "\e[39m        $(ip route | grep -m1 -o -P 'src \K[0-9,.]*'):8383 \e[39m" "\e[35m(IP-of-PI:8383) \e[39m"
echo " "
echo -e "\e[32m(6) Command to see Status\e[39m sudo systemctl status aiscatcher"
echo -e "\e[32m(7) Command to Restart\e[39m    sudo systemctl restart aiscatcher"