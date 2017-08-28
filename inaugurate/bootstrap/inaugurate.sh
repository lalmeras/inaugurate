#!/usr/bin/env bash

# Exit codes:
# 2: application configuration error
# 3: execution error somewhere in the bootstrap pipeline
# 6: platform or package manager not supported

#set -o pipefail

if [ ! -z "$INAUGURATE_DEBUG" ]; then
    DEBUG=true
fi
if [ "$DEBUG" = true ]; then
    set -x
fi

# prepare pip, conda & apt channels if necessary
# PIP_INDEX_URL=""
# CONDA_CHANNEL=""

#PIP_INDEX_URL=
#CONDA_CHANNEL=
CHINA=true
if [ "$CHINA" = true ]; then
  PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
  CONDA_CHANNEL="https://mirrors.tuna.tsinghua.edu.cn/anaconda/pkgs/free/"
fi

# # convert exitcodes to events
# # trap "throw EXIT"    EXIT
# # trap "throw SIGINT"  SIGINT
# # trap "throw SIGTERM" SIGTERM

# addListener VIRTUALENV_ERROR error_message
# addListener CONDA_ERROR error_message

trap 'error_exit "Bootstrapping interrupted, exiting...; exit"' SIGHUP SIGINT SIGTERM

PROGNAME="inaugurate"
function error_exit
{

    #	----------------------------------------------------------------
    #	Function for exit due to fatal program error
    #		Accepts 1 argument:
    #			string containing descriptive error message
    #	----------------------------------------------------------------


	  error_output "${PROGNAME}: ${1:-"Unknown Error"}" 1>&2
	  exit 1
}

# determine whether we run with sudo, or not
if [ "$EUID" != 0 ]; then
    root_permissions=false
    INAUGURATE_USER="$USER"
else
    root_permissions=true
    if [ -z "$SUDO_USER" ]; then
          if [ ! -z "$USER" ]; then
            INAUGURATE_USER="$USER"
          else
            INAUGURATE_USER="root"
          fi
    else
        INAUGURATE_USER="$SUDO_USER"
    fi
fi


# echo "ROOT_PERMISSIONS: $root_permissions"
# echo "INAUGURATE_USER: $INAUGURATE_USER"

if [ ! -z "$1" ]; then
    PROFILE_NAME=`basename "$1"`
else
    PROFILE_NAME="inaugurate"
fi

# inaugurate vars
# conda
INAUGURATE_CONDA_PYTHON_VERSION="2.7"
INAUGURATE_CONDA_DEPENDENCIES="pip cryptography pycrypto git"
INAUGURATE_CONDA_EXECUTABLES_TO_LINK="$PROFILE_NAME"
# deb
INAUGURATE_DEB_DEPENDENCIES="build-essential git python-dev python-virtualenv libssl-dev libffi-dev"
# rpm
INAUGURATE_RPM_DEPENDENCIES="epel-release wget git python-virtualenv openssl-devel gcc libffi-devel python-devel ope  nssl-devel"
# pip requirements
INAUGURATE_PIP_DEPENDENCIES="inaugurate"

# profile dependent
if [ "$PROFILE_NAME" == "frkl" ]; then
  # conda
  EXECUTABLE_NAME="frkl"
  CONDA_PYTHON_VERSION="2.7"
  CONDA_DEPENDENCIES="pip git"
  EXECUTABLES_TO_LINK="$PROFILE_NAME"
  # deb
  DEB_DEPENDENCIES="build-essential git python-dev python-virtualenv libssl-dev libffi-dev"
  # rpm
  RPM_DEPENDENCIES="epel-release wget git python-virtualenv openssl-devel gcc libffi-devel python-devel"
  # pip requirements
  PIP_DEPENDENCIES="pyyaml frkl"
  VENV_NAME="inaugurate"
  CONDA_ENV_NAME="inaugurate"
  #elif [ "$PROFILE_NAME" == "freckles" ] || [ "$PROFILE_NAME" == "inaugurate" ]; then
else
  # conda
  EXECUTABLE_NAME="$PROFILE_NAME"
  CONDA_PYTHON_VERSION="2.7"
  CONDA_DEPENDENCIES="pip cryptography pycrypto git"
  EXECUTABLES_TO_LINK="freckles frecklecute"
  EXTRA_EXECUTABLES="nsbl nsbl-tasks nsbl-playbook ansible ansible-playbook ansible-galaxy git"
  # deb
  DEB_DEPENDENCIES="curl build-essential git python-dev python-virtualenv libssl-dev libffi-dev"
  # rpm
  RPM_DEPENDENCIES="epel-release wget git python-virtualenv openssl-devel gcc libffi-devel python-devel"
  # pip requirements
  PIP_DEPENDENCIES="freckles"
  VENV_NAME="inaugurate"
  CONDA_ENV_NAME="inaugurate"
fi

# General variables
DEBUG=false

INAUGURATE_USER_HOME="`eval echo ~$INAUGURATE_USER`"

INAUGURATE_BASE_DIR="$INAUGURATE_USER_HOME/.inaugurate"
BASE_DIR="$INAUGURATE_USER_HOME/.local"
INSTALL_LOG_DIR="$INAUGURATE_BASE_DIR/.install_logs"
SCRIPT_LOG_FILE="$INSTALL_LOG_DIR/install.log"
INAUGURATE_OPT="$BASE_DIR/inaugurate"
TEMP_DIR="$INAUGURATE_BASE_DIR/tmp/"

LOCAL_BIN_PATH="$BASE_DIR/bin"
INAUGURATE_BIN_PATH="$INAUGURATE_OPT/bin"

# python/virtualenv related variables
VIRTUALENV_DIR="$INAUGURATE_OPT/virtualenvs/$VENV_NAME"
VIRTUALENV_PATH="$VIRTUALENV_DIR/bin"

# conda related variables
CONDA_DOWNLOAD_URL_LINUX="https://repo.continuum.io/miniconda/Miniconda2-latest-Linux-x86_64.sh"
CONDA_DOWNLOAD_URL_MAC="https://repo.continuum.io/miniconda/Miniconda2-latest-MacOSX-x86_64.sh"
CONDA_BASE_DIR="$BASE_DIR/inaugurate/conda"
INAUGURATE_CONDA_PATH="$CONDA_BASE_DIR/bin"
CONDA_ROOT_EXE="$CONDA_BASE_DIR/bin/conda"
CONDA_INAUGURATE_ENV_PATH="$CONDA_BASE_DIR/envs/$CONDA_ENV_NAME"
CONDA_INAUGURATE_ENV_EXE="$CONDA_INAUGURATE_ENV_PATH/bin/conda"

mkdir -p "$INSTALL_LOG_DIR"
touch "$SCRIPT_LOG_FILE"
chmod 700 "$SCRIPT_LOG_FILE"
chown -R "$INAUGURATE_USER" "$INAUGURATE_BASE_DIR"


function log () {
    echo "    .. $@" >> "$SCRIPT_LOG_FILE"
}

function output() {
    log "$@"
    if ! [ "${QUIET}" = true ]; then
      echo "$@"
    fi
}

function error_output() {
    log $1
    (>&2 echo "$@")
}

function command_exists {
    PATH="$PATH:$LOCAL_BIN_PATH:$INAUGURATE_BIN_PATH" type "$1" > /dev/null 2>&1 ;
}

function execute_log {
    eval "$1" >> "$SCRIPT_LOG_FILE" 2>&1 || error_exit "$2"
}

function download {
    {
    if command_exists wget; then
        execute_log "wget -O $2 $1" "Could not download $1 using wget"
    elif command_exists curl; then
        execute_log "curl -o $2 $1" "Could not download $1 using curl"
    else
        error_output "Could not find 'wget' nor 'curl' to download files. Exiting..."
        exit 1
    fi
    } >> "$SCRIPT_LOG_FILE"
}

function install_inaugurate {
    if [ "$1" = true ]; then
        install_inaugurate_root
    else
        install_inaugurate_non_root_conda
    fi
}

#TODO: exception handline for this
function create_virtualenv {
    {
    su "$INAUGURATE_USER" <<EOF
set +e
mkdir -p "$INAUGURATE_OPT"
if [ ! -e "$VIRTUALENV_DIR" ]; then
  virtualenv --system-site-packages "$VIRTUALENV_DIR"
fi
source "$VIRTUALENV_DIR/bin/activate"
pip install --upgrade pip
pip install --upgrade setuptools wheel
pip install --upgrade requests
set -e
EOF
    } >> "$SCRIPT_LOG_FILE" 2>&1 || error_exit "Could not create '$VENV_NAME' virtual environment"
}

#TODO: exception handling for this
#TODO: check whether package already installed? or overkill? -- yeah, probably
function install_package_in_virtualenv {
    output "    -> installing '$1' into venv: $VIRTUALENV_DIR"
    {
        su "$INAUGURATE_USER" <<EOF
set +e
source "$VIRTUALENV_DIR/bin/activate"
pip install --upgrade "$1" --upgrade-strategy only-if-needed
set -e
EOF
    } >> "$SCRIPT_LOG_FILE" 2>&1 || error_exit "Could not create '$VENV_NAME' virtual environment"
}


function install_inaugurate_deb {
    output "  * Debian-based system detected"
    output "  * updating apt cache"
    # sometimes, on a new debian machine, the first (and even 2nd) 'apt-get update' fails...
    execute_log "apt-get update || apt-get update" "Could not update apt repository cache"
    output "  * installing dependencies:$DEB_DEPENDENCIES"
    execute_log "apt-get install -y $DEB_DEPENDENCIES" "Error installing dependencies via apt."
    output "  * creating '$VENV_NAME' virtual environment"
    create_virtualenv
    for pkgName in $PIP_DEPENDENCIES
    do
        install_package_in_virtualenv $pkgName
    done
    link_required_executables "$VIRTUALENV_PATH" "$EXECUTABLES_TO_LINK"
    link_extra_executables "$VIRTUALENV_PATH" "$EXTRA_EXECUTABLES"
    #export PATH="$PATH:$VIRTUALENV_PATH"
}

function install_inaugurate_rpm {
    output "  * RedHat-based system detected."
    output "  * installing dependencies: $RPM_DEPENDENCIES"
    execute_log "yum install -y epel-release" "Error installing dependencies via yum."
    execute_log "yum install -y $RPM_DEPENDENCIES" "Error installing dependencies via yum."
    output "  * creating '$VENV_NAME' virtual environment"
    create_virtualenv
    for pkgName in $PIP_DEPENDENCIES
    do
        install_package_in_virtualenv $pkgName
    done
    link_required_executables "$VIRTUALENV_PATH" "$EXECUTABLES_TO_LINK"
    link_extra_executables "$VIRTUALENV_PATH" "$EXTRA_EXECUTABLES"
    #export PATH="$PATH:$VIRTUALENV_PATH"
}

function install_commandlinetools {
    g++ --version > /dev/null 2>&1
    if [ ! $? -eq 0 ]; then
        output "  * installing CommandLineTools"
        output "    -> looking up package name and version... "
        sudo -u "$INAUGURATE_USER" touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
        log "Finding command-line-tools name"
        PROD=$(softwareupdate -l |
               grep "\*.*Command Line" |
               head -n 1 | awk -F"*" '{print $2}' |
               sed -e 's/^ *//' |
               tr -d '\n')
        output "    -> installing: $PROD..."
        execute_log "sudo -u \"$INAUGURATE_USER\" softwareupdate -i \"$PROD\" " "Could not install $PROD"
        rm /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
    else
        output "  - 'xcode' already present, skipping"
    fi

}

function install_inaugurate_mac_root {
    output '  * MacOS X-based system detected.'
    install_commandlinetools
    output "  * installing pip & virtualenv"
    if ! command_exists pip; then
        execute_log "easy_install pip" "Could not install pip"
    fi
    if ! command_exists virtualenv; then
        execute_log "pip install virtualenv" "Could not install virtualenv via pip"
    fi

    output "  * creating '$VENV_NAME' virtual environment"
    create_virtualenv
    for pkgName in $PIP_DEPENDENCIES
    do
        install_package_in_virtualenv $pkgName
    done
    link_required_executables "$VIRTUALENV_PATH" "$EXECUTABLES_TO_LINK"
    link_extra_executables "$VIRTUALENV_PATH" "$EXTRA_EXECUTABLES"
    #export PATH="$PATH:$VIRTUALENV_PATH"
}

function install_inaugurate_linux_root {
    YUM_CMD=$(which yum 2> /dev/null)
    APT_GET_CMD=$(which apt-get 2> /dev/null)
    if [[ ! -z $YUM_CMD ]]; then
        install_inaugurate_rpm
    elif [[ ! -z $APT_GET_CMD ]]; then
        install_inaugurate_deb
    else
        error_output "Could not find supported package manager. Exiting..."
        exit 6
    fi
}

function install_inaugurate_root {

    output "  * elevated permissions detected, using sytem package manager to install dependencies"

    # figure out which os we are running
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        install_inaugurate_linux_root
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        install_inaugurate_mac_root
    elif [[ "$OSTYPE" == "cygwin" ]]; then
        # POSIX compatibility layer and Linux environment emulation for Windows
        error_output "Sorry, Cygwin platform is not supported (at the moment, anyway). Exiting..."
        exit 6
    elif [[ "$OSTYPE" == "msys" ]]; then
        # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
        error_output "Sorry, msys/MinGW platform is not supported (at the moment, anyway). Exiting..."
        exit 6
    elif [[ "$OSTYPE" == "win32" ]]; then
        error_output "Sorry, win32 platform is not supported (at the moment, anyway). Exiting..."
        exit 6
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
        error_output "Sorry, freebsd platform is not supported (at the moment, anyway). Exiting..."
        exit 6
    else
        error_output "Could not figure out which platform I'm running on. Exiting..."
        exit 6
    fi
}

function link_path {
    rm -f "$3/$2"
    log "  * linking $1/$2 to $3/$2"
    ln -s "$1/$2" "$3/$2"
}

function link_path_to_local_bin {
    link_path "$1" "$2" "$LOCAL_BIN_PATH"
}

function link_path_to_inaugurate_bin {
    link_path "$1" "$2" "$INAUGURATE_BIN_PATH"
}

function link_conda_executables {

    for pkgName in conda activate deactivate
    do
        link_path_to_local_bin "$INAUGURATE_CONDA_PATH" "$pkgName"
    done
}

function link_required_executables {

    for pkgName in $2
    do
        link_path_to_local_bin "$1" "$pkgName"
    done
}

function link_extra_executables {

    for pkgName in $2
    do
        link_path_to_inaugurate_bin "$1" "$pkgName"
    done
}

function install_inaugurate_non_root_conda {

    output "  * no elevated permissions detected, using conda package manager"

    if [ ! -f "$CONDA_ROOT_EXE" ]; then
        output "  * installing conda"
        install_conda_non_root
    else
        output "  - 'conda' already present, not installing again"
        #export PATH="$INAUGURATE_CONDA_PATH:$PATH"
    fi

    if [ ! -e "$CONDA_INAUGURATE_ENV_EXE" ]; then
        output "  * creating '$CONDA_ENV_NAME' conda environment"
        execute_log "$CONDA_ROOT_EXE create -y --name $CONDA_ENV_NAME python=$CONDA_PYTHON_VERSION" "Could not create conda environment."
    else
        output "  - '$CONDA_ENV_NAME' conda environment already exists, not creating again"
    fi

    packages=`$CONDA_ROOT_EXE list --name "$CONDA_ENV_NAME"`

    # check python in conda environment
     if echo "$packages" | grep -q "^python\s*$CONDA_PYTHON_VERSION"; then
       output "    -> python already present in conda environment '$CONDA_ENV_NAME'"
     else
       output "    -> installing python (version $CONDA_PYTHON_VERSION) into conda environment '$CONDA_ENV_NAME'"
       execute_log "$CONDA_ROOT_EXE install --name $CONDA_ENV_NAME -y python=$CONDA_PYTHON_VERSION" "Could not install python in conda environment."
    fi

    # check conda dependencies
    for pkgName in $CONDA_DEPENDENCIES
    do
        if echo $packages | grep -q "$pkgName"; then
            output "    -> package '$pkgName' already present in conda environment '$CONDA_ENV_NAME'"
         else
            output "    -> installing $pkgName into conda environment '$CONDA_ENV_NAME'"
            execute_log "$CONDA_ROOT_EXE install --name $CONDA_ENV_NAME -y $pkgName" "Could not install $pkgName in conda environment."
         fi
    done

    execute_log "source $INAUGURATE_CONDA_PATH/activate $CONDA_ENV_NAME" "Could not activate '$CONDA_ENV_NAME' conda environment"

    for pkgName in $PIP_DEPENDENCIES
    do
        modules=`$INAUGURATE_CONDA_PATH/pydoc modules`
        if echo "$modules" | grep -q "$pkgName" ; then
           output "    -> python package '$pkgName' already present in conda environment '$CONDA_ENV_NAME'"
        else
            output "    -> installing python package '$pkgName' into conda environment '$CONDA_ENV_NAME'"
            execute_log "pip install -U $pkgName --upgrade-strategy only-if-needed" "Could not install $pkgName in conda environment"
        fi

    done
    execute_log "source deactivate $CONDA_ENV_NAME" "Could not deactivate '$CONDA_ENV_NAME' conda environment"
    link_conda_executables
    link_required_executables "$CONDA_INAUGURATE_ENV_PATH/bin" "$EXECUTABLES_TO_LINK"
    link_extra_executables "$CONDA_INAUGURATE_ENV_PATH/bin" "$EXTRA_EXECUTABLES"
}

function install_conda_non_root {
    output "  * bootstrapping conda package manager"
    {
    cd "$TEMP_DIR"
    if [[ "$OSTYPE" == "linux-gnu" ]]; then
        download "$CONDA_DOWNLOAD_URL_LINUX" "$TEMP_DIR/miniconda.sh"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        download "$CONDA_DOWNLOAD_URL_MAC" "$TEMP_DIR/miniconda.sh"
    fi
    } >> "$SCRIPT_LOG_FILE" 2>&1
    mkdir -p "$INAUGURATE_OPT"
    output "  * installing conda"
    {
    bash "$TEMP_DIR/miniconda.sh" -b -p "$CONDA_BASE_DIR"
    #export PATH="$INAUGURATE_CONDA_PATH:$PATH"
    cd "$HOME"
    rm -rf "$TEMP_DIR"
    } >> "$SCRIPT_LOG_FILE" 2>&1
}

function add_inaugurate_path {
    if [ ! -e "$INAUGURATE_USER_HOME/.profile" ] || ! grep -q 'add inaugurate environment' "$INAUGURATE_USER_HOME/.profile"; then
       cat <<"EOF" >> "$INAUGURATE_USER_HOME/.profile"

# add inaugurate environment
LOCAL_BIN_PATH="$HOME/.local/bin"
if [ -d "$LOCAL_BIN_PATH" ]; then
    PATH="$PATH:$LOCAL_BIN_PATH"
fi
EOF

       output "Added path to inaugurate bin dir to .profile. You'll need to logout and login again to see the effect. Or you can just execute:"
       output ""
       output "   source ~/.profile"
    fi
}

############# Start script ##################

export PATH="$LOCAL_BIN_PATH:$INAUGURATE_BIN_PATH:$PATH"

execute_log "echo Starting inaugurate bootstrap: `date`" "Error"

# prepare pip, conda and apt mirrors if necessary
if [ $CHINA = 'true' ]; then
    CONDA_DOWNLOAD_URL_LINUX="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda2-latest-Linux-x86_64.sh"
    CONDA_DOWNLOAD_URL_MAC="https://mirrors.tuna.tsinghua.edu.cn/anaconda/miniconda/Miniconda2-latest-MacOSX-x86_64.sh"
fi

if [ -n "$PIP_INDEX_URL" ] && [ ! -e "$INAUGURATE_USER_HOME/.pip/pip.conf" ]; then
    output ""
    output "* setting pip index to: $PIP_INDEX_URL"
    mkdir -p "$INAUGURATE_USER_HOME/.pip"
    echo "[global]" > "$INAUGURATE_USER_HOME/.pip/pip.conf"
    echo "index-url = $PIP_INDEX_URL" >> "$INAUGURATE_USER_HOME/.pip/pip.conf"
fi

if [ -n "$CONDA_CHANNEL" ] && [ ! -e "$INAUGURATE_USER_HOME/.condarc" ]; then
    output ""
    output "* setting conda channel to: $CONDA_CHANNEL"
    echo "channels:" > "$INAUGURATE_USER_HOME/.condarc"
    echo "  - $CONDA_CHANNEL" >> "$INAUGURATE_USER_HOME/.condarc"
    echo "show_channel_urls: true" >> "$INAUGURATE_USER_HOME/.condarc"
fi

if [[ $CHINA = 'true' && ( "$root_permissions" = true || "$INAUGURATE_USER" == "root" ) ]]; then
    output "setting apt sources to ftp.cn.debian.org mirror"
    if [ ! -e /etc/apt/sources.list.bak.inaugurate ]; then
        sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak.inaugurate
    fi
    sudo sed -i 's/deb.debian.org/ftp.cn.debian.org/g' /etc/apt/sources.list
fi

# check if command is already in the path, if it is, assume everything is bootstrapped
if ! command_exists $EXECUTABLE_NAME; then

    if ! command_exists "inaugurate"; then
      output ""
      output "'inaugurate' not found in path, bootstrapping..."
      mkdir -p "$TEMP_DIR"
      mkdir -p "$LOCAL_BIN_PATH"
      mkdir -p "$INAUGURATE_BIN_PATH"
      if [ $root_permissions = true ]; then
          chown -R "$INAUGURATE_USER" "$BASE_DIR"
          chown -R "$INAUGURATE_USER" "$TEMP_DIR"
          chown -R "$INAUGURATE_USER" "$LOCAL_BIN_PATH"
          chown -R "INAUGURATE_USER" "$INAUGURATE_BIN_PATH"
      fi
      output ""
      install_inaugurate "$root_permissions"
      output ""
      add_inaugurate_path
    fi
    if ! command_exists $EXECUTABLE_NAME; then
        output "'$EXECUTABLE_NAME' not found in path, inaugurating..."
        inaugurate "$1"
    fi
    shift
    output ""
    output "Bootstrappings finished, now attempting to run '$EXECUTABLE_NAME' (like so: '$EXECUTABLE_NAME $@')"
    output ""
    output "========================================================================"
    output ""
else
    shift
fi

execute_log "echo Finished '$PROFILE_NAME' bootstrap: `date`" "Error"

#echo "INAUGURATE_PATH: $LOCAL_BIN_PATH"

if [ "$root_permissions" = true ] && [ "$INAUGURATE_USER" != "root" ]; then
    #exec sudo -u "$INAUGURATE_USER" -i "PATH=$PATH:$LOCAL_BIN_PATH:$INAUGURATE_BIN_PATH" "$EXECUTABLE_NAME" "$@"
    exec sudo -u "$INAUGURATE_USER" "$LOCAL_BIN_PATH/$EXECUTABLE_NAME" "$@"
else
    PATH="$PATH:$LOCAL_BIN_PATH:$INAUGURATE_BIN_PATH" "$EXECUTABLE_NAME" "$@"
fi
