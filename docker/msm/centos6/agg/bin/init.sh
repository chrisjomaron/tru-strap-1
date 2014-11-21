#!/bin/bash
#
# init.sh       Provision MSM/TSM trustrap services.
#
# Authors:      Jim Davies, <Jim.Davies@moneysupermarket.com>
#               Paul Gilligan, <Paul.Gilligan@moneysupermarket.com>
#
# Description:  Install MSM/TSM based puppet provisioning software and 
#               provision the required puppet role. This script has been modified from the original concept to allow many applications
#               to be provisioned under a vagrant/docker hosted solution.
#
#               This has beed designed to be re-entrant, i.e. it can be re-run.    
# 
# Original:     https://github.com/MSMFG/tru-strap
# Git version:  https://github.com/pauldavidgilligan-msm/tru-strap
# Git branch:   handsome-vagrant-docker

# Usage:        ./init.sh -r agg-redis -e dev -u pauldavidgilligan-msm -n msm-provisioning -b handsome-vagrant-docker

NOW=$(date "+%Y_%m_%d_%H")
VERSION=0.0.3
SCRIPTNAME=`basename $0`
SKYDNS_NAME=go-skydns
PROGRESS_LOG=/tmp/progress_${NOW}.log
PROCESS_CONF=/etc/supervisord.conf

export LC_ALL=en_GB.utf8

echo $(date "+%Y-%m-%d %H:%M:%S") "Docker Provision Start" > ${PROGRESS_LOG}

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
function _line {
  length=40
  printf -v line '%*s' "$length"
  echo ${line// /=}
}

function _bold {
  echo -e "\e[30;1m$1 \e[21m"
  echo $(date "+%Y-%m-%d %H:%M:%S") $1 >> ${PROGRESS_LOG}
}

function _err {
  length=40
  printf -v line '%*s' "$length"
  echo ${line// /-}
  echo -e "\e[31m$1 \e[39m"
  echo $(date "+%Y-%m-%d %H:%M:%S") $1 >> ${PROGRESS_LOG}
}

function usage {
cat <<EOF

    Usage: $0 [options]
    -h| --help             this usage text.
    -v| --version          the version.
    -r| --role             the trustrap role
    -e| --environment      the environment name.
    -u| --repouser         the git repository user name.
    -n| --reponame         the git repository name.
    -b| --repobranch       the git repository branch name.
    
EOF
}

# -----------------------------------------------------------------------------
# Reset console
# -----------------------------------------------------------------------------
echo -e "\e[0m"
_line

# -----------------------------------------------------------------------------
# Process Command Line Params
# -----------------------------------------------------------------------------
while test -n "$1"; do
  case "$1" in
  --help|-h)
    usage
    exit
    ;;
  --version|-v)
    echo $SCRIPTNAME $VERSION
    exit
    ;;
  --role|-r)
    TRUSTRAP_ROLE=$2
    shift
    ;;
  --environment|-e)
    TRUSTRAP_ENV=$2
    shift
    ;;
  --repouser|-u)
    TRUSTRAP_REPOUSER=$2
    shift
    ;;
  --reponame|-n)
    TRUSTRAP_REPONAME=$2
    shift
    ;;
  --repobranch|-b)
    TRUSTRAP_REPOBRANCH=$2
    shift
    ;;

  *)
    _err ", unknown argument: $1"
    usage
    exit 1
    ;;
  esac
  shift
done

# -----------------------------------------------------------------------------
# Check
# -----------------------------------------------------------------------------
grep -q "${SKYDNS_NAME}" "${PROCESS_CONF}"
if [[ $? -eq 0 ]] ;
then
  printf ", skipped due to ${SKYDNS_NAME} ${PROCESS_CONF}"
  exit
fi

_bold "Verifying ${SCRIPTNAME}"
if [[ ${TRUSTRAP_ROLE} == "" || ${TRUSTRAP_ENV} == "" || ${TRUSTRAP_REPOUSER} == "" || ${TRUSTRAP_REPONAME} == "" || ${TRUSTRAP_REPOBRANCH} == "" ]]; then
  _err ", missing argument(s)."
  usage
  exit 1
fi

# -----------------------------------------------------------------------------
# Run 
# -----------------------------------------------------------------------------
_bold "Running ${SCRIPTNAME}"
TRUSTRAP_REPODIR="/opt/${TRUSTRAP_REPONAME}"
if [[ -d "${TRUSTRAP_REPODIR}" ]]; then
  rm -rf "${TRUSTRAP_REPODIR}"
  echo "Removed previous git repostory ${TRUSTRAP_REPODIR}"
fi

# -----------------------------------------------------------------------------
# Extra tools
# -----------------------------------------------------------------------------
yum install -y htop

# -----------------------------------------------------------------------------
# Git clone
# -----------------------------------------------------------------------------
GITCMD="git clone --progress -b ${TRUSTRAP_REPOBRANCH} git@github.com:${TRUSTRAP_REPOUSER}/${TRUSTRAP_REPONAME}.git ${TRUSTRAP_REPODIR}"
PUPPET_DIR="${TRUSTRAP_REPODIR}/puppet"
PUPPET_BASE_FILE="Puppetfile.base"
PUPPET_BASE_ROLE_FILE="Puppetfile.${TRUSTRAP_ROLE}"

if [[ ! -d /root/.ssh ]]; then
  echo "Add github.com to known_hosts"
  mkdir /root/.ssh && touch /root/.ssh/known_hosts && ssh-keyscan -H github.com >> /root/.ssh/known_hosts && chmod 600 /root/.ssh/known_hosts
fi
_bold "Git: ${GITCMD}"
`${GITCMD}`

# -----------------------------------------------------------------------------
# Puppet
# -----------------------------------------------------------------------------
_bold "Installing trustrap puppet from ${PUPPET_DIR}"
rm -rf /etc/puppet ; ln -s ${PUPPET_DIR} /etc/puppet 
rm /etc/hiera.yaml ; ln -s /etc/puppet/hiera.yaml /etc/hiera.yaml

_bold "Installing trustrap puppet security from ${PUPPET_DIR}"
mkdir -p /etc/puppet/secure/keys
chmod 0500 /etc/puppet/secure/
chmod 0500 /etc/puppet/secure/keys
cd /etc/puppet/secure/
eyaml createkeys
# TODO: @Paul dev keys ?

_bold "Installing puppet role ${TRUSTRAP_ROLE}"
if [[ ! -f /etc/puppet/Puppetfiles/${PUPPET_BASE_FILE} ]] || [[ ! -f /etc/puppet/Puppetfiles/${PUPPET_BASE_ROLE_FILE} ]]; then
  _err "Error locating puppet role file /etc/puppet/Puppetfiles/${PUPPET_BASE_FILE}"
  _err "Error locating puppet role file /etc/puppet/Puppetfiles/${PUPPET_BASE_ROLE_FILE}"
  _err "Check files and role name, ${TRUSTRAP_ROLE}"
  exit 1
fi
cat /etc/puppet/Puppetfiles/${PUPPET_BASE_FILE} /etc/puppet/Puppetfiles/${PUPPET_BASE_ROLE_FILE} > /etc/puppet/Puppetfile
cd /etc/puppet
librarian-puppet install --verbose
librarian-puppet show
echo -e "\e[0m"

# -----------------------------------------------------------------------------
# Set factor values 
# -----------------------------------------------------------------------------
_bold "Set Facter values"
mkdir -m 0600 -p /etc/facter/facts.d
echo "# trustrap generated custom values"       > /etc/facter/facts.d/init_custom_values.txt
echo "init_env=${TRUSTRAP_ENV}"                >> /etc/facter/facts.d/init_custom_values.txt
echo "init_role=${TRUSTRAP_ROLE}"              >> /etc/facter/facts.d/init_custom_values.txt
echo "init_repouser=${TRUSTRAP_REPOUSER}"      >> /etc/facter/facts.d/init_custom_values.txt
echo "init_reponame=${TRUSTRAP_REPONAME}"      >> /etc/facter/facts.d/init_custom_values.txt
echo "init_repobranch=${TRUSTRAP_REPOBRANCH}"  >> /etc/facter/facts.d/init_custom_values.txt

echo "msmid_env=${TRUSTRAP_ENV}"                >> /etc/facter/facts.d/init_custom_values.txt
echo "msmid_role=${TRUSTRAP_ROLE}"              >> /etc/facter/facts.d/init_custom_values.txt
echo "msmid_repouser=${TRUSTRAP_REPOUSER}"      >> /etc/facter/facts.d/init_custom_values.txt
echo "msmid_reponame=${TRUSTRAP_REPONAME}"      >> /etc/facter/facts.d/init_custom_values.txt
echo "msmid_repobranch=${TRUSTRAP_REPOBRANCH}"  >> /etc/facter/facts.d/init_custom_values.txt

# -----------------------------------------------------------------------------
# Pull the puppet string
# -----------------------------------------------------------------------------
_bold "Provison with puppet apply"
figlet -f digital TruStrap

puppet apply /etc/puppet/manifests/site.pp

_line
_bold "${SCRIPTNAME} Complete"
_line

