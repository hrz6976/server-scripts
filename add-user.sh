#!/bin/bash

# This script is used to create a new user on the local system.
# You will be prompted to enter the username (login), the person name, and a password.
# The username, password, and host for the account will be displayed.
# Make sure you execute the script with superuser privileges.
# If you do not supply at least one argument, then you will be prompted for the value.
# Run the script like this:
# sudo ./add-local-user.sh USERNAME [AUTHORIZED KEYS]...

set -e

# Make sure the script is being executed with superuser privileges.
if [[ "${UID}" -ne 0 ]]
then
  echo 'Please run with sudo or as root.' >&2
  exit 1
fi

# If the user doesn't supply at least one argument, then give them help.
if [[ "${#}" -lt 1 ]]
then
  echo "Usage: ${0} USERNAME [AUTHORIZED KEYS]..." >&2
  echo 'Create an account on the local system with the name of USER_NAME and a public key with AUTHORIZED KEYS.' >&2
  exit 1
fi

# The first parameter is the user name.
USERNAME=${1}

# The rest of the parameters are for public keys.
shift
AUTHORIZED_KEYS=${@}

# prompt for user id
read -p "Enter the user id (UID) or leave blank for default: " USER_UID

# Create the user with the password.
if [[ -z "${USER_UID}" ]]; then
  useradd -m ${USERNAME}
else
  groupadd -g ${USER_UID} ${USERNAME}
  useradd -u ${USER_UID} -g ${USER_UID} -m ${USERNAME}
fi

# Check to see if the useradd command succeeded.
# We don't want to tell the user that an account was created when it hasn't been.
if [[ "${?}" -ne 0 ]]
then
  echo 'The account could not be created.' >&2
  exit 1
fi

# Generate a password. (Steam vericode style, replace: 0->8, O->9)
PASSWORD=$(openssl rand 3 | base32 | head -c5 | sed 's/0/8/g' | sed 's/O/9/g')
echo "${USERNAME}:${PASSWORD}" | chpasswd ${USERNAME}
# Check to see if the passwd command succeeded.
if [[ "${?}" -ne 0 ]]
then
  echo 'The password for the account could not be set.' >&2
  exit 1
fi
# Force password change on first login.
passwd -e ${USERNAME}

# Create the .ssh directory if it does not exist.
if [[ ! -d "/home/${USERNAME}/.ssh" ]]
then
  mkdir /home/${USERNAME}/.ssh
fi
if [[ ! -z "${AUTHORIZED_KEYS}" ]]
then
  # Copy the authorized keys to the .ssh directory.
  echo "${AUTHORIZED_KEYS}" > /home/${USERNAME}/.ssh/authorized_keys
fi
# Set the ownership of the .ssh directory.
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh
# Set the permissions of the .ssh directory.
chmod 700 /home/${USERNAME}/.ssh

# prompt: add the user to sudoers?
read -p "Add ${USERNAME} to sudoers? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
  # Add the user to sudoers.
  usermod -aG sudo ${USERNAME}
fi

# change the default shell
if [[ ! -z $(which zsh) ]]
then
  read -p "Change the default shell to zsh? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    # Change the default shell to zsh.
    chsh -s /bin/zsh ${USERNAME}
  else
    # set the default shell to bash
    chsh -s /bin/bash ${USERNAME}
  fi
else
  # set the default shell to bash
  chsh -s /bin/bash ${USERNAME}
fi

# create user folders
read -p "Create user folders? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
  # Create user folders. (unified)
  for folder in "/data" "/raid" "/fast"
  do
    if [[ -d ${folder} && ! -d "${folder}/${USERNAME}" ]]
    then
      mkdir -p "${folder}/${USERNAME}"
      echo "Created user folder: ${folder}/${USERNAME}"
      chown -R ${USERNAME}:${USERNAME} "${folder}/${USERNAME}"
    fi
  done
fi

# Display the username, password, and the host where the user was created.
echo "Username: ${USERNAME}"
echo "Password: ${PASSWORD}"
echo "Host: $(hostname) ($(hostname -I | cut -d' ' -f1))"
echo "Authorized: $(cut -d' ' -f3 /home/${USERNAME}/.ssh/authorized_keys)"