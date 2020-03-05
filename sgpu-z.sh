#!/bin/bash

#H
#H  sgpu-z.sh
#H
#H  DESCRIPTION
#H    This script is a simple approach to the GPU-Z program to show,
#H  monitor and log the status of a GPUs. Now it support only NVIDIA GPUs.
#H    It also allows control of some overclocking parameters, like power 
#H  limit, gpu & memory frequency, even voltage if possible. And also creates
#H  a script to load the overclocking parameters automatically. It only uses
#H the NVIDIA tools: nvidia-smi, nvidia-settings
#H
#H  USAGE
#H    sgpu-z.sh [-h] [-d] -i value
#H
#H  ARGUMENTS
#H    -d --doc     Optional. Documentation.
#H    -h --help    Optional. Help information.
#H

#D  COPYRIGHT: Riventek
#D  LICENSE:   GPLv2
#D  AUTHOR:    franky@riventek.com
#D
#D  REFERENCES
#D    [1] http://developer.download.nvidia.com/compute/DCGM/docs/nvidia-smi-367.38.pdf
#D    [2] https://wiki.archlinux.org/index.php/NVIDIA/Tips_and_tricks
#D    [3] https://www.phoronix.com/scan.php?page=news_item&px=MTg0MDI
#D    [4] ftp://download.nvidia.com/XFree86/Linux-x86/1.0-6106/nvidia-settings-user-guide.txt
#D    [5] https://github.com/NVIDIA/nvidia-settings
#D    [6] http://www.computerhope.com/unix/utput.htm
#D    [7] 
#D

#########################################################################
# GENERAL SETUP
#########################################################################   
# Exit on error. Append || true if you expect an error.
set -o errexit 
# Exit on error inside any functions or subshells.
set -o errtrace
# Do not allow use of undefined vars. Use ${VAR:-} to use an undefined VAR
set -o nounset
# Catch the error in case any command in a pipe fails. e.g. mysqldump fails (but gzip succeeds) in `mysqldump |gzip`
set -o pipefail
# Trap signals to have a clean exit
trap clean_exit SIGHUP SIGINT SIGTERM
# Turn on traces, useful while debugging but commented out by default
# set -o xtrace

#########################################################################
# VARIABLES SETUP 
#########################################################################
readonly RK_SCRIPT=$0              # Store the script name for help() and doc() functions
readonly RK_HAS_MANDATORY_ARGUMENTS="NO" #"YES" # or "NO"
readonly TMPFILE=$(mktemp)         # Generate the temporary mask
# Add the commands and libraries required for the script to run
RK_DEPENDENCIES="sed grep tput stty tr setterm glxinfo"
RK_LIBRARIES=""

# CODES FOR TERMINAL - Optimized for compatibility - use printf also for better compatibility
# Styles
readonly BOLD="\e[1m"
readonly BOLD_OFF="\e[21m"
readonly UNDERLINE="\e[4m"
readonly UNDERLINE_OFF="\e[24m"
readonly REVERSE="\e[7m"
readonly REVERSE_OFF="\e[27m"
readonly STYLE_OFF="\e[0m"

# Colors Foreground
readonly FG_BLACK="\e[30m"
readonly FG_RED="\e[31m"
readonly FG_GREEN="\e[32m"
readonly FG_YELLOW="\e[33m"
readonly FG_BLUE="\e[34m"
readonly FG_MAGENTA="\e[35m"
readonly FG_CYAN="\e[36m"
readonly FG_LIGHTGREY="\e[37m"
readonly FG_DARKGREY="\e[90m"
readonly FG_LIGHTRED="\e[91m"
readonly FG_LIGHTGREEN="\e[92m"
readonly FG_LIGHTYELLOW="\e[93m"
readonly FG_LIGHTBLUE="\e[94m"
readonly FG_LIGHTMAGENTA="\e[95m"
readonly FG_LIGHTCYAN="\e[96m"
readonly FG_WHITE="\e[97m"
readonly FG_DEFAULT="\e[39m"

# Colors Background
readonly BG_BLACK="\e[40m"
readonly BG_RED="\e[41m"
readonly BG_GREEN="\e[42m"
readonly BG_YELLOW="\e[43m"
readonly BG_BLUE="\e[44m"
readonly BG_MAGENTA="\e[45m"
readonly BG_CYAN="\e[46m"
readonly BG_LIGHTGREY="\e[47m"
readonly BG_DARKGREY="\e[100m"
readonly BG_LIGHTRED="\e[101m"
readonly BG_LIGHTGREEN="\e[102m"
readonly BG_LIGHTYELLOW="\e[103m"
readonly BG_LIGHTBLUE="\e[104m"
readonly BG_LIGHTMAGENTA="\e[105m"
readonly BG_LIGHTCYAN="\e[106m"
readonly BG_WHITE="\e[107m"
readonly BG_DEFAULT="\e[49m"

# ## SCRIPT VARIABLES ##

# Default Variables for command line
export DISPLAY_DATA=1
export LOGGING="OFF"
echo "$LOGGING" > $TMPFILE-logging # Used to share the status across threads

#########################################################################
# BASIC FUNCTIONS FOR ALL SCRIPTS
#########################################################################
# Function to extract the help usage from the script
help () {
	grep '^[ ]*[\#]*H' ${RK_SCRIPT} | sed 's/^[ ]*[\#]*H//g' | sed 's/^  //'
}
# Function to extract the documentation from the script
doc () {
  grep '^[ ]*[\#][\#]*[HDF]' ${RK_SCRIPT} | sed 's/^[ ]*[\#]*F / \>/g;s/^[ ]*[\#]*[HDF]//g' | sed 's/^  //'
}
# Function to print the errors and warnings
echoerr() {
  echo -e ${RK_SCRIPT}" [$(date +'%Y-%m-%d %H:%M:%S')] $@" >&2
}
# Function to clean-up when exiting
clean_exit() {
    local exit_code

    export DISPLAY_DATA=0	
    setterm -cursor on
    
    if [ "${1:-}" == "" ]; then
        exit_code=0
    else
        exit_code=$(( $1 ))
    fi

    printf "\n${FG_GREEN}>> [$exit_code] Cleaning up ... ${STYLE_OFF}"
    if [[ ${TMPFILE:-} != "" ]]; then
        rm -f ${TMPFILE:-}*
    fi
    printf "DONE !\n\n"

    exit $exit_code
}
# Function to check availability and load the required libraries
check_libraries() {
  if [[ ${RK_LIBRARIES:-} != "" ]]; then
	  for library in ${RK_LIBRARIES:-}; do
	    local missing=0
	    if [[ -r ${library} ]]; then
		    source ${library}
	    else
		    echoerr "> Required library  not found: ${library}"
		    let missing+=1
	    fi
	    if [[ ${missing} -gt 0 ]]; then
		    echoerr "** ERROR **: Cannot found ${missing} required libraries, aborting\n"
		    clean_exit 1
	    fi
	  done
  fi
}
# Function to check if the required dependencies are available
check_dependencies() {
  local missing=0
  if [[ ${RK_DEPENDENCIES:-} != "" ]]; then
	  for command in ${RK_DEPENDENCIES}; do
	    if ! hash "${command}" >/dev/null 2>&1; then
		    echoerr "> Required Command not found in PATH: ${command}"
		    let missing+=1
	    fi
	  done
	  if [[ ${missing} -gt 0 ]]; then
	    echoerr "** ERROR **: Cannot found ${missing} required commands are missing in PATH, aborting\n"
	    clean_exit 1
	  fi
  fi
}

#D ## SCRIPT FUNCTIONS ##

# Simple wrapper to the nvidia-smi command to do error checking
nvsmi()
{
    sudo nvidia-smi "$@" 2>$TMPFILE-error.log
    if [ $? -ne 0 ]; then
        case $ in
            2)
                echoerr "** nvidia-smi ERROR **: A supplied argument or flag is invalid."
                ;;
            3)
                echoerr "** nvidia-smi ERROR **: The requested operation is not available on target device."
                ;;
            4)
                echoerr "** nvidia-smi ERROR **: The current user does not have permission to access this device or perform this operation."
                ;;
            6)
                echoerr "** nvidia-smi ERROR **: A query to find an object was unsuccessful."
                ;;
            8)
                echoerr "** nvidia-smi ERROR **: A device's external power cables are not properly attached."
                ;;
            9)
                echoerr "** nvidia-smi ERROR **: NVIDIA driver is not loaded."
                ;;
            10)
                echoerr "** nvidia-smi ERROR **: NVIDIA Kernel detected an interrupt issue with a GPU."
                ;;
            12)
                echoerr "** nvidia-smi ERROR **: NVML Shared Library couldn't be found or loaded."
                ;;
            13)
                echoerr "** nvidia-smi ERROR **: Local version of NVML doesn't implement this function."
                ;;
            14)
                echoerr "** nvidia-smi ERROR **: infoROM is corrupted."
                ;;
            15)
                echoerr "** nvidia-smi ERROR **: The GPU has fallen off the bus or has otherwise become inaccessible."
                ;;
            *)
                echoerr "** nvidia-smi ERROR **: Other error or internal driver error occurred !"
                ;;
        esac
        echoerr  " >> Command: $@"
        clean_exit -1
    fi
}

# Simple wrapper to the nvidia-settings command to do error checking
nvsettings()
{
    local nvserror

    sudo nvidia-settings "$@" 2>$TMPFILE-nvsettings-error.log
    if [ -s $TMPFILE-nvsettings-error.log ]; then
        # Observed an error but it sets the offset
        if [ "$(grep ERROR $TMPFILE-nvsettings-error.log | grep $GPU_CLOCK_OFFSET_ATTRIBUTE | grep Unknown)" != "" ]; then
            echo "" > $TMPFILE-nvsettings-error.log
        fi
        if [ "$(grep ERROR $TMPFILE-nvsettings-error.log )" != "" ]; then
            nvserror=$(cut -f2 -d':' $TMPFILE-nvsettings-error.log | tr -d '\n' | tr -s ' ')
            echoerr "** nvidia-settings ERROR **: $nvserror"
            clean_exit -1
        fi
    fi
}

#F
#F  FUNCTION:    graphics_card
#F  DESCRIPTION: This function will handle the interaction with the Graphics Card
#F  GLOBALS
#F    DISPLAY       The display id to use
#F    CARD_VENDOR   The graphics card Vendor
#F    ID_GPU        The graphics card ID selected
#F  ARGUMENTS
#F    $1     Command to execute
#F
graphics_card()
{
    local command
    local parameters
    local coolbits
    local answer
    tmpfile=${TMPFILE}-${FUNCNAME[0]}

    # If no arguments, then just initialize and check functionality
    if [[ "${1:-}" == "" ]]; then
        command="initialize"
    else
        command="$1"
        shift
    fi
    parameters="${@:-}"

    # Main function code
    case "$CARD_VENDOR" in
        NVIDIA)
            case "$command" in
                initialize)

                    # Execute nvidia-smi & nvidia-settings to ensure there is no error
                    nvsmi -q | tr -s '\n' > $tmpfile
                    nvsettings -q all | tr -s '\n' >> $tmpfile

		    # Locate xorg.conf
		    XORGCONFFILE=$(grep xorg.conf /var/log/Xorg.$(echo $DISPLAY | cut -f2 -d":").log | cut -f2 -d"\"")
                    echo ">> X Configuration from $XORGCONFFILE !"
		    if [ -d $XORGCONFFILE ]; then
			XORGCONFFILE=$XORGCONFFILE/xorg.conf
		    fi
		    if [ ! -e $XORGCONFFILE ]; then
			    sudo touch $XORGCONFFILE
		    fi
                    echo ">> Setting X Configuration to $XORGCONFFILE !"

                    # Check if there is Coolbits enabled
                    if [ "$(grep -i coolbits $XORGCONFFILE ) " == " " ]; then
                        echo ">> No coolbits in Xorg.conf !"
                        coolbits=0
                    else
                        coolbits=$(( $(grep -i coolbits $XORGCONFFILE | tr -s ' ' | tr -d '"' | cut -f4 -d ' ') ))
                    fi

                    # Check if Coolbits have all the desired values
                    if [ $coolbits -lt 28 ]; then
                        printf "${REVERSE}WARNING:${REVERSE_OFF} - ${FG_YELLOW}NVIDIA Coolbits not enabled or not set at optimum setting.${FG_DEFAULT}\n${FG_LIGHTBLUE}Do you want to set it (Y/n)? "
                        read answer
                        printf "${STYLE_OFF}\n"
                        if [ "$answer" == "" ] || [ "$answer" == "Y" ] || [ "$answer" == "y" ]; then
                            sudo nvidia-xconfig --cool-bits=28 -c $XORGCONFFILE -o $XORGCONFFILE --allow-empty-initial-configuration
                            printf "${FG_GREEN}Please re-start X Server to make it work :) !${STYLE_OFF}\n\n"
                            clean_exit 0
                        fi
                    fi

                    # We will check which chip we have to set the correct overclocking attribute
                    if [ "${GPU_CLOCK_OFFSET_ATTRIBUTE:-}" == "" ]; then
                        if [ "$(nvsettings -q [gpu:$ID_GPU]/GPUGraphicsClockOffsetAllPerformanceLevels)" != "" ] ; then
                            # Seems to be a Pascal Chip or upper: we can change the offset of all performance levels
                            printf "${FG_GREEN}Seems to be a Pascal or upper Chip: we can Overclock all levels !!! ..  ${STYLE_OFF}\n"
                            GPU_CLOCK_OFFSET_ATTRIBUTE="GPUGraphicsClockOffsetAllPerformanceLevels"
                            MEMORY_CLOCK_OFFSET_ATTRIBUTE="GPUMemoryTransferRateOffsetAllPerformanceLevels"
                        else
                            # Seems to be a Maxwell Chip or previous chip : we can change the only the offset highest performance level
                            printf "${FG_GREEN}Seems to be a Fermi, Kepler or Maxwell Chip: we only can overclock some level ...${STYLE_OFF}\n"
                            GPU_CLOCK_OFFSET_ATTRIBUTE="GPUGraphicsClockOffset[3]"
                            MEMORY_CLOCK_OFFSET_ATTRIBUTE="GPUMemoryTransferRateOffset[3]"
                        fi

                        # Get an store the Clock/Memory Offset max/min values
                        GPU_CLOCK_OFFSET_MIN=$(nvsettings -q [gpu:$ID_GPU]/$GPU_CLOCK_OFFSET_ATTRIBUTE | tr -d '\n' | tr -s ' '| grep range | sed 's/range/#/' | cut -f2 -d'#' | sed 's/ \- /(/' | cut -f1 -d'('| tr -d ' ')
                        GPU_CLOCK_OFFSET_MAX=$(nvsettings -q [gpu:$ID_GPU]/$GPU_CLOCK_OFFSET_ATTRIBUTE |tr -d '\n' | tr -s ' '| grep range | sed 's/range/#/' | cut -f2 -d'#' | sed 's/ \- /(/' | cut -f2 -d'('| tr -d ' ')
                        MEMORY_CLOCK_OFFSET_MIN=$(nvsettings -q [gpu:$ID_GPU]/$MEMORY_CLOCK_OFFSET_ATTRIBUTE |tr -d '\n' | tr -s ' '| grep range | sed 's/range/#/' | cut -f2 -d'#' | sed 's/ \- /(/' | cut -f1 -d'('| tr -d ' ')
                        MEMORY_CLOCK_OFFSET_MAX=$(nvsettings -q [gpu:$ID_GPU]/$MEMORY_CLOCK_OFFSET_ATTRIBUTE | tr -d '\n' | tr -s ' '| grep range | sed 's/range/#/' | cut -f2 -d'#' | sed 's/ \- /(/' | cut -f2 -d'('| tr -d ' ')
                    fi

                    # Check if modifying the voltage is possible
                    if [ "${GPU_VOLTAGE_AVAILABLE:-}" == "" ]; then
                        if [ "$(nvsettings -q [gpu:$ID_GPU]/GPUOverVoltageOffset | tr -d '\n' )" == "" ]; then
                            printf "${FG_GREEN}Voltage Control seems NOT available :( ${STYLE_OFF}\n"
                            GPU_VOLTAGE_AVAILABLE=FALSE
                            CORE_VOLTAGE_MIN_OFFSET="N/A"
                            CORE_VOLTAGE_MAX_OFFSET="N/A"
                        else
                            printf "${FG_GREEN}Voltage Control seems IS available :) ${STYLE_OFF}\n"
                            GPU_VOLTAGE_AVAILABLE=TRUE
                            CORE_VOLTAGE_MIN_OFFSET=$(printf "%0.1f mV\n" $(echo "$(nvsettings -q [gpu:$ID_GPU]/GPUOverVoltageOffset | tr -d '\n' | tr -s ' '| grep range | sed 's/range/#/' | cut -f2 -d'#' | sed 's/ \- /(/' | cut -f1 -d'('| tr -d ' ')/1000"| bc -l) )
                            CORE_VOLTAGE_MAX_OFFSET=$(printf "%0.1f mV\n" $(echo "$(nvsettings -q [gpu:$ID_GPU]/GPUOverVoltageOffset | tr -d '\n' | tr -s ' '| grep range | sed 's/range/#/' | cut -f2 -d'#' | sed 's/ \- /(/' | cut -f2 -d'('| tr -d ' ')/1000"| bc -l) )
                        fi
                    fi
                    printf "${FG_GREEN}Initialization and Check OK :D !!${FG_DEFAULT}"
                    ;;
                list-gpus)
                    nvsmi -L
                    ;;
                product-name)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=gpu_name
                    ;;
                vbios-version)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=vbios_version
                    ;;
                device-id)
                    echo "$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=pci.device_id)-$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=pci.sub_device_id)"
                    ;;
                computing-cores)
                    nvsettings -t -q [gpu:$ID_GPU]/CUDACores
                    ;;
                memory-size)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=memory.total
                    ;;
                pci-info)
                    echo "PCI-E $(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=pcie.link.gen.max).0x$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=pcie.link.width.max) @ $(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=pcie.link.gen.current).0x$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=pcie.link.width.current) $(echo "scale=1;$(nvsettings -t -q [gpu:$ID_GPU]/PCIECurrentLinkSpeed)/1000" | bc -l)GT/s"
                    ;;
                power-gpu)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=power.draw
                    ;;
                power-default)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=power.default_limit
                    ;;
                power-management)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=power.management
                    ;;
                power-limit)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=power.limit
                    ;;
                power-limit-set)
                    if [ $(echo "$parameters" | cut -f1 -d' ' | cut -f1 -d'.') -le $(graphics_card power-max | cut -f1 -d' ' | cut -f1 -d'.') ] && \
                       [ $(echo "$parameters" | cut -f1 -d' ' | cut -f1 -d'.') -ge $(graphics_card power-min | cut -f1 -d' ' | cut -f1 -d'.') ] ; then
                        nvsmi -i $ID_GPU  -pl $(echo "$parameters" | cut -f1 -d' ')
                    fi
                    ;;
                power-max)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=power.max_limit
                    ;;
                power-min)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=power.min_limit
                    ;;
                driver-version)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=driver_version
                    ;;
                inforom-version)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=inforom.img
                    ;;
                gpu-clock)
                    #nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=clocks.current.graphics
                    printf "%3d" $(nvsettings -t -q [gpu:$ID_GPU]/GPUCurrentClockFreqs| grep ','| cut -f1 -d',')
                    ;;
                gpu-clock-default)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=clocks.default_applications.graphics
                    ;;
                gpu-clock-max)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=clocks.max.graphics
                    ;;
                gpu-clock-offset)
                    nvsettings -t -q [gpu:$ID_GPU]/$GPU_CLOCK_OFFSET_ATTRIBUTE
                    ;;
                gpu-clock-offset-set)
                    nvsettings -a [gpu:$ID_GPU]/$GPU_CLOCK_OFFSET_ATTRIBUTE=$(echo "$parameters" | cut -f1 -d' ')
                    ;;
                memory-clock)
                    #nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=clocks.current.memory
                    printf "%3d" $(nvsettings -t -q [gpu:$ID_GPU]/GPUCurrentClockFreqs| grep ','| cut -f2 -d',')
                    ;;
                memory-clock-default)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=clocks.default_applications.memory
                    ;;
                memory-clock-max)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=clocks.max.memory
                    ;;
                memory-clock-offset)
                    nvsettings -t -q [gpu:$ID_GPU]/$MEMORY_CLOCK_OFFSET_ATTRIBUTE
                    ;;
                memory-clock-offset-set)
                    nvsettings -a [gpu:$ID_GPU]/$MEMORY_CLOCK_OFFSET_ATTRIBUTE=$(echo "$parameters" | cut -f1 -d' ')
                    ;;
                get-modes)
                    echo "Display:${FG_GREEN} "$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=display_mode)"${STYLE_OFF} P${REVERSE}e${REVERSE_OFF}rsistence:${FG_GREEN}${REVERSE} "$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=persistence_mode)"${STYLE_OFF} ${REVERSE}A${REVERSE_OFF}ccounting:${FG_GREEN}${REVERSE} "$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=accounting.mode)"${STYLE_OFF}"
                    ;;
                performance-state)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=pstate
                    ;;
                core-voltage)
                    if [ $GPU_VOLTAGE_AVAILABLE == TRUE ]; then
                        printf "%0.1f mV\n" $(echo "$(nvsettings -t -q [gpu:$ID_GPU]/GPUCurrentCoreVoltage)/1000" | bc -l)
                    else
                        echo " 0 "
                    fi
                    ;;
                core-voltage-offset)
                    if [ $GPU_VOLTAGE_AVAILABLE == TRUE ]; then
                        printf "%0.1f mV\n" $(echo "$(nvsettings -t -q [gpu:$ID_GPU]/GPUOverVoltageOffset)/1000" | bc -l)
                    else
                        echo "N/A"
                    fi
                    ;;
                core-voltage-offset-raw)
                    if [ $GPU_VOLTAGE_AVAILABLE == TRUE ]; then
                        nvsettings -t -q [gpu:$ID_GPU]/GPUOverVoltageOffset
                    else
                        echo 0
                    fi
                    ;;
                core-voltage-offset-set)
                    if [ $GPU_VOLTAGE_AVAILABLE == TRUE ]; then
                        nvsettings -a [gpu:$ID_GPU]/GPUOverVoltageOffset=$(echo "$parameters" | cut -f1 -d' ')
                    fi
                    ;;
                powermizer-mode)
                    case $(nvsettings -t -q [gpu:$ID_GPU]/GPUPowerMizerMode) in
                         0)
                             echo "Adaptative             "
                             ;;
                         1)
                             echo "Pref. Max. Performance "
                             ;;
                         2)
                             echo "Auto                   "
                             ;;
                         3)
                             echo "Pref. Cons. Performance"
                             ;;
                         *)
                             echo "Unknown                "
                    esac
                    ;;
                powermizer-mode-raw)
                    nvsettings -t -q [gpu:$ID_GPU]/GPUPowerMizerMode
                    ;;
                powermizer-mode-set)
                    nvsettings -a [gpu:$ID_GPU]/GPUPowerMizerMode=$(echo "$parameters" | cut -f1 -d' ')
                    ;;
                gpu-temperature)
                    echo "$(nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=temperature.gpu) C"
                    ;;
                gpu-temperature-shutdown)
                    nvsmi -i $ID_GPU --display=TEMPERATURE --query  | grep Shutdown | cut -f 2 -d':'
                    ;;
                gpu-temperature-slowdown)
                    nvsmi -i $ID_GPU --display=TEMPERATURE --query  | grep Slowdown | cut -f 2 -d':'
                    ;;
                gpu-throttle-reasons)
                    nvsmi -i $ID_GPU --display=PERFORMANCE --query | grep ":[ ]*Active" | cut -f1 -d':' | sed 's/^[ ]*//g' | sed 's/[ ]*$//g'| tr '\n' '|' | sed 's/[\|]*$//'
                    ;;
                gpu-usage)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=utilization.gpu | sed 's/%/%%/'
                    ;;
                memory-usage)
                    nvsmi -i $ID_GPU  --format=csv,noheader --query-gpu=utilization.memory | sed 's/%/%%/'
                    ;;
                fan-control-get)
                    nvsettings -t -q [gpu:$ID_GPU]/GPUFanControlState
                    ;;
                fan-control-set)
                    nvsettings -t -a [gpu:$ID_GPU]/GPUFanControlState=1
                    ;;
                fan-control-reset)
                    nvsettings -t -a [gpu:$ID_GPU]/GPUFanControlState=0
                    ;;
                fan-target-speed-get)
                    echo $(nvsettings -t -q [fan:$ID_GPU]/GPUTargetFanSpeed) "%%"
                    ;;
                fan-target-speed-set)
                    nvsettings -a [fan:$ID_GPU]/GPUTargetFanSpeed=$(echo "$parameters" | cut -f1 -d' ')
                    ;;
                fan-current-speed)
                    echo $(nvsettings -t -q [fan:$ID_GPU]/GPUCurrentFanSpeed) "%%"
                    ;;
                fan-current-speed-rpm)
		    TMPRPM=$(( $(nvsettings -t -q [fan:$ID_GPU]/GPUCurrentFanSpeedRPM) ))
		    # Filter some aberrant readings in some cards
		    if [ $TMPRPM -gt 5000 ]; then
			    TMPRPM=$FAN_CURRENT_SPEED_RPM
	            fi
                    echo "$TMPRPM RPM"
                    ;;
                *)
                    echo "N/A"
                    ;;
            esac
            ;;
        *)
            echoerr "** ERROR **: Card Vendor $CARD_VENDOR is not (yet) supported !"
            clean_exit -1
            ;;
    esac

    # Cleaning up
    rm -Rf ${tmpfile}*
}

#F
#F  FUNCTION:    reset_sensor_stats
#F  DESCRIPTION: This function will reset the sensor statistics
#F  GLOBALS
#F    SAMPLE_COUNT
#F    GPU_CLOCK GPU_CLOCK_SMAX GPU_CLOCK_SMIN GPU_CLOCK_AVG
#F    GPU_TEMP GPU_TEMP_SMAX GPU_TEMP_SMIN GPU_TEMP_AVG
#F    MEMORY_CLOCK MEMORY_CLOCK_SMAX MEMORY_CLOCK_SMIN MEMORY_CLOCK_AVG
#F    POWER_GPU POWER_GPU_SMAX POWER_GPU_SMIN POWER_GPU_AVG
#F    FAN_CURRENT_SPEED FAN_CURRENT_SPEED_SMAX FAN_CURRENT_SPEED_SMIN FAN_CURRENT_SPEED_AVG
#F    GPU_USAGE GPU_USAGE_SMAX GPU_USAGE_SMIN GPU_USAGE_AVG
#F    MEMORY_USAGE MEMORY_USAGE_SMAX MEMORY_USAGE_SMIN MEMORY_USAGE_AVG
#F
reset_sensor_stats()
{
  # Main function code
    SAMPLE_COUNT=1

    GPU_CLOCK_N=$(graphics_card gpu-clock | cut -f1 -d' ')
    GPU_CLOCK_SMAX=$GPU_CLOCK_N
    GPU_CLOCK_SMIN=$GPU_CLOCK_N
    GPU_CLOCK_AVG=$GPU_CLOCK_N

    GPU_TEMP_N=$(graphics_card gpu-temperature | cut -f1 -d' ')
    GPU_TEMP_SMAX=$GPU_TEMP_N
    GPU_TEMP_SMIN=$GPU_TEMP_N
    GPU_TEMP_AVG=$GPU_TEMP_N

    MEMORY_CLOCK_N=$(graphics_card memory-clock | cut -f1 -d' ')
    MEMORY_CLOCK_SMAX=$MEMORY_CLOCK_N
    MEMORY_CLOCK_SMIN=$MEMORY_CLOCK_N
    MEMORY_CLOCK_AVG=$MEMORY_CLOCK_N

    POWER_GPU_N=$(graphics_card power-gpu | cut -f1 -d' '| cut -f1 -d'.')
    POWER_GPU_SMAX=$POWER_GPU_N
    POWER_GPU_SMIN=$POWER_GPU_N
    POWER_GPU_AVG=$POWER_GPU_N

    FAN_CURRENT_SPEED_N=$(graphics_card fan-current-speed | cut -f1 -d' ')
    FAN_CURRENT_SPEED_SMAX=$FAN_CURRENT_SPEED_N
    FAN_CURRENT_SPEED_SMIN=$FAN_CURRENT_SPEED_N
    FAN_CURRENT_SPEED_AVG=$FAN_CURRENT_SPEED_N

    GPU_USAGE_N=$(graphics_card gpu-usage | cut -f1 -d' ')
    GPU_USAGE_SMAX=$GPU_USAGE_N
    GPU_USAGE_SMIN=$GPU_USAGE_N
    GPU_USAGE_AVG=$GPU_USAGE_N

    MEMORY_USAGE=$(graphics_card memory-usage | cut -f1 -d' ')
    MEMORY_USAGE_SMAX=$MEMORY_USAGE
    MEMORY_USAGE_SMIN=$MEMORY_USAGE
    MEMORY_USAGE_AVG=$MEMORY_USAGE

    if [ $GPU_VOLTAGE_AVAILABLE == TRUE ]; then
        CORE_VOLTAGE_N=$(graphics_card core-voltage | cut -f1 -d' ' | cut -f1 -d'.')
        CORE_VOLTAGE_SMAX=$CORE_VOLTAGE_N
        CORE_VOLTAGE_SMIN=$CORE_VOLTAGE_N
        CORE_VOLTAGE_AVG=$CORE_VOLTAGE_N
    else
        CORE_VOLTAGE_N=$(graphics_card core-voltage)
        CORE_VOLTAGE_SMAX=$CORE_VOLTAGE_N
        CORE_VOLTAGE_SMIN=$CORE_VOLTAGE_N
        CORE_VOLTAGE_AVG=$CORE_VOLTAGE_N
    fi
}

#F
#F  FUNCTION:    update_sensor_stats
#F  DESCRIPTION: This function will update the sensor statistics calculating the average, maximum and minimum
#F  GLOBALS
#F    SAMPLE_COUNT
#F    GPU_CLOCK GPU_CLOCK_SMAX GPU_CLOCK_SMIN GPU_CLOCK_AVG
#F    GPU_TEMP GPU_TEMP_SMAX GPU_TEMP_SMIN GPU_TEMP_AVG
#F    MEMORY_CLOCK MEMORY_CLOCK_SMAX MEMORY_CLOCK_SMIN MEMORY_CLOCK_AVG
#F    POWER_GPU POWER_GPU_SMAX POWER_GPU_SMIN POWER_GPU_AVG
#F    FAN_CURRENT_SPEED FAN_CURRENT_SPEED_SMAX FAN_CURRENT_SPEED_SMIN FAN_CURRENT_SPEED_AVG
#F    GPU_USAGE GPU_USAGE_SMAX GPU_USAGE_SMIN GPU_USAGE_AVG
#F    MEMORY_USAGE MEMORY_USAGE_SMAX MEMORY_USAGE_SMIN MEMORY_USAGE_AVG
#F
update_sensor_stats()
{
    # Main function code

    # Reset stats if needed
    if [ "${SAMPLE_COUNT:-}" == "" ] || [ -f $TMPFILE-reset_sensor_stats ]; then
        reset_sensor_stats
        rm -f $TMPFILE-reset_sensor_stats
    fi

    GPU_CLOCK_N=$(echo $GPU_CLOCK | cut -f1 -d' ')
    if [ $GPU_CLOCK_N -gt $GPU_CLOCK_SMAX ]; then
        GPU_CLOCK_SMAX=$GPU_CLOCK_N
    fi
    if [ $GPU_CLOCK_N -lt $GPU_CLOCK_SMIN ]; then
        GPU_CLOCK_SMIN=$GPU_CLOCK_N
    fi
    GPU_CLOCK_AVG=$( echo "($GPU_CLOCK_AVG * $SAMPLE_COUNT + $GPU_CLOCK_N)/($SAMPLE_COUNT + 1)" | bc -l )

    GPU_TEMP_N=$(echo $GPU_TEMP  | cut -f1 -d' ')
    if [ $GPU_TEMP_N -gt $GPU_TEMP_SMAX ]; then
        GPU_TEMP_SMAX=$GPU_TEMP_N
    fi
    if [ $GPU_TEMP_N -lt $GPU_TEMP_SMIN ]; then
        GPU_TEMP_SMIN=$GPU_TEMP_N
    fi
    GPU_TEMP_AVG=$( echo "($GPU_TEMP_AVG * $SAMPLE_COUNT + $GPU_TEMP_N)/($SAMPLE_COUNT + 1)" | bc -l )

    MEMORY_CLOCK_N=$(echo $MEMORY_CLOCK  | cut -f1 -d' ')
    if [ $MEMORY_CLOCK_N -gt $MEMORY_CLOCK_SMAX ]; then
        MEMORY_CLOCK_SMAX=$MEMORY_CLOCK_N
    fi
    if [ $MEMORY_CLOCK_N -lt $MEMORY_CLOCK_SMIN ]; then
        MEMORY_CLOCK_SMIN=$MEMORY_CLOCK_N
    fi
    MEMORY_CLOCK_AVG=$( echo "($MEMORY_CLOCK_AVG * $SAMPLE_COUNT + $MEMORY_CLOCK_N)/($SAMPLE_COUNT + 1)" | bc -l)

    POWER_GPU_N=$(echo $POWER_GPU  | cut -f1 -d' '| cut -f1 -d'.')
    if [ $POWER_GPU_N -gt $POWER_GPU_SMAX ]; then
        POWER_GPU_SMAX=$POWER_GPU_N
    fi
    if [ $POWER_GPU_N -lt $POWER_GPU_SMIN ]; then
        POWER_GPU_SMIN=$POWER_GPU_N
    fi
    POWER_GPU_AVG=$( echo "($POWER_GPU_AVG * $SAMPLE_COUNT + $POWER_GPU_N)/($SAMPLE_COUNT + 1)" | bc -l )

    FAN_CURRENT_SPEED_N=$(echo $FAN_CURRENT_SPEED_RPM  | cut -f1 -d' ')
    if [ $FAN_CURRENT_SPEED_N -gt $FAN_CURRENT_SPEED_SMAX ]; then
        FAN_CURRENT_SPEED_SMAX=$FAN_CURRENT_SPEED_N
    fi
    if [ $FAN_CURRENT_SPEED_N -lt $FAN_CURRENT_SPEED_SMIN ]; then
        FAN_CURRENT_SPEED_SMIN=$FAN_CURRENT_SPEED_N
    fi
    FAN_CURRENT_SPEED_AVG=$( echo "($FAN_CURRENT_SPEED_AVG * $SAMPLE_COUNT + $FAN_CURRENT_SPEED_N)/($SAMPLE_COUNT + 1)" | bc -l )

    GPU_USAGE_N=$(echo $GPU_USAGE  | cut -f1 -d' ')
    if [ $GPU_USAGE_N -gt $GPU_USAGE_SMAX ]; then
        GPU_USAGE_SMAX=$GPU_USAGE_N
    fi
    if [ $GPU_USAGE_N -lt $GPU_USAGE_SMIN ]; then
        GPU_USAGE_SMIN=$GPU_USAGE_N
    fi
    GPU_USAGE_AVG=$( echo "($GPU_USAGE_AVG * $SAMPLE_COUNT + $GPU_USAGE_N)/($SAMPLE_COUNT + 1)" | bc -l )

    MEMORY_USAGE_N=$(echo $MEMORY_USAGE  | cut -f1 -d' ')
    if [ $MEMORY_USAGE_N -gt $MEMORY_USAGE_SMAX ]; then
        MEMORY_USAGE_SMAX=$MEMORY_USAGE_N
    fi
    if [ $MEMORY_USAGE_N -lt $MEMORY_USAGE_SMIN ]; then
        MEMORY_USAGE_SMIN=$MEMORY_USAGE_N
    fi
    MEMORY_USAGE_AVG=$( echo "($MEMORY_USAGE_AVG * $SAMPLE_COUNT + $MEMORY_USAGE_N)/($SAMPLE_COUNT + 1)" | bc -l )

    if [ $GPU_VOLTAGE_AVAILABLE == TRUE ]; then
        CORE_VOLTAGE_N=$(echo $CORE_VOLTAGE | cut -f1 -d' ' | cut -f1 -d'.')
        if [ $CORE_VOLTAGE_N -gt $CORE_VOLTAGE_SMAX ]; then
            CORE_VOLTAGE_SMAX=$CORE_VOLTAGE_N
        fi
        if [ $CORE_VOLTAGE_N -lt $CORE_VOLTAGE_SMIN ]; then
            CORE_VOLTAGE_SMIN=$CORE_VOLTAGE_N
        fi
        CORE_VOLTAGE_AVG=$( echo "($CORE_VOLTAGE_AVG * $SAMPLE_COUNT + $CORE_VOLTAGE_N)/($SAMPLE_COUNT + 1)" | bc -l )
    fi

    let SAMPLE_COUNT+=1
}

#########################################################################
# MAIN SCRIPT
#########################################################################
tput clear
printf "\n>> [SGPU-Z] Starting up !"
# Check & Load required libraries
check_libraries

# Command Line Parsing
echo -e "\n"
if [[ "${1:-}" == "" ]] && [[ ${RK_HAS_MANDATORY_ARGUMENTS} = "YES" ]]; then
  help
  clean_exit 1
else
  while [[ "${1:-}" != "" ]]
  do
	  case $1 in
      -i)
		    shift
		    value=$1
		    # We expect and extra value after the -i option
		    echo "- Setting value=$value"
		    shift
		    ;;
      -d|--doc)  
		    shift
		    doc
		    clean_exit 0
		    ;;
      -h|--help)
		    shift
		    help
		    clean_exit 0
		    ;;
      *)
		    help
		    clean_exit 1
		    ;;
	  esac
  done
fi

# Check if we have all the required commands
check_dependencies

# Check for Display settings
echo ">> Checking Display variables ..."
if [ "${DISPLAY:-}" == "" ]; then
    printf "${REVERSE}WARNING${REVERSE_OFF} - ${FG_YELLOW}DISPLAY variable not set !${FG_DEFAULT}\n"
    printf "${FG_LIGHTBLUE}Input the DISPLAY to check (remember to add the ':'): "
    read DISPLAY
    export DISPLAY
    printf "${STYLE_OFF}\n"
else
    printf "${FG_GREEN}OK !${FG_DEFAULT}\n\n"
fi
# Get the Vendor from the Graphics Card
echo ">> Getting Card Vendor ..."
export CARD_VENDOR=$(glxinfo | grep -i "opengl vendor" | cut -f2 -d':' | cut -f2 -d' ')
if [ $? -ne 0 ]; then
    echoerr "** ERROR **: Could not access to display $DISPLAY !"
    clean_exit -1
else
    printf "${FG_GREEN}Card Vendor: $CARD_VENDOR${STYLE_OFF}\n\n"
fi

if [ "${ID_GPU:-}" == "" ]; then
    # Look if we have more than 1 GPU to check
    let NGPUS=$(( $(graphics_card list-gpus | wc -l) ))
    if [ $NGPUS -gt 1 ]; then
        printf "${REVERSE}WARNING${REVERSE_OFF} - ${FG_YELLOW}More than one GPU detected !${FG_DEFAULT}\n"
        graphics_card list-gpus
        printf "${FG_LIGHTBLUE}Input the GPU to check (only the ID number): "
        read ID_GPU
        printf "${STYLE_OFF}\n"
    else
        ID_GPU=0
    fi
fi

# According to the vendor, assign the required utilities
case "$CARD_VENDOR" in
    NVIDIA)
        RK_DEPENDENCIES="nvidia-smi nvidia-settings nvidia-xconfig"
        ;;
    *)
        echoerr "** ERROR **: Card Vendor $CARD_VENDOR is not (yet) supported !"
        clean_exit -1
        ;;
esac
# Check if we have all the required commands
check_dependencies


# Check the graphics card access
echo ">> Initialization and Checking Graphics Card access ..."
graphics_card initialize

#####
###

# Use 'printf' for portability ;)
printf "\n\n${FG_LIGHTBLUE}Ready to Start ?${FG_DEFAULT} Press ${REVERSE}ENTER${REVERSE_OFF} !"; read START

# Ensure we are not echoing any keyboard character & hide the cursor
setterm -cursor off

# Static Graphics Card Information
PRODUCT_NAME=$(graphics_card product-name)
VBIOS_VERSION=$(graphics_card vbios-version)
DEVICE_ID=$(graphics_card device-id)
COMPUTING_CORES=$(graphics_card computing-cores)
MEMORY_SIZE=$(graphics_card memory-size)
DRIVER_VERSION=$(graphics_card driver-version)
INFOROM_VERSION=$(graphics_card inforom-version)
POWER_MANAGEMENT=$(graphics_card power-management)
POWER_MAX=$(graphics_card power-max)
POWER_MIN=$(graphics_card power-min)
GPU_TEMP_SLOWDOWN=$(graphics_card gpu-temperature-slowdown)
GPU_TEMP_SHUTDOWN=$(graphics_card gpu-temperature-shutdown)

tput clear
reset_sensor_stats

#
# Main Display Thread 
#
{
    while [ $DISPLAY_DATA -eq 1 ]; do

        # Reset the terminal and go to Home
        tput cup 0 0    
    
        # Graphics Card Dynamic Information to be refreshed
        PCI_INFO=$(graphics_card pci-info)
        POWER_GPU=$(graphics_card power-gpu)
        POWER_LIMIT=$(graphics_card power-limit)
        GPU_CLOCK=$(graphics_card gpu-clock)
        GPU_CLOCK_MAX=$(graphics_card gpu-clock-max)
        GPU_CLOCK_OFFSET=$(graphics_card gpu-clock-offset)
        MEMORY_CLOCK=$(graphics_card memory-clock)
        MEMORY_CLOCK_MAX=$(graphics_card memory-clock-max)
        MEMORY_CLOCK_OFFSET=$(graphics_card memory-clock-offset)
        CORE_VOLTAGE=$(graphics_card core-voltage)
        CORE_VOLTAGE_OFFSET=$(graphics_card core-voltage-offset)
        PERFORMANCE_STATE=$(graphics_card performance-state)
        POWERMIZER_MODE=$(graphics_card powermizer-mode)
        GPU_TEMP=$(graphics_card gpu-temperature)
        GPU_THROTTLE=$(graphics_card gpu-throttle-reasons)
        GPU_USAGE=$(graphics_card gpu-usage)
        MEMORY_USAGE=$(graphics_card memory-usage)
        FAN_CONTROL=$(graphics_card fan-control-get)
        FAN_TARGET_SPEED=$(graphics_card fan-target-speed-get)
        FAN_CURRENT_SPEED=$(graphics_card fan-current-speed)
        FAN_CURRENT_SPEED_RPM=$(graphics_card fan-current-speed-rpm)
        update_sensor_stats
        
        # First we print static information
        printf "${FG_LIGHTBLUE}=============================|${BOLD} SGPU-Z ${STYLE_OFF}${FG_LIGHTBLUE}|============================${STYLE_OFF}\n"
        printf "Vendor:${FG_GREEN} $CARD_VENDOR  ${FG_DEFAULT}Name:${FG_GREEN} $PRODUCT_NAME ${FG_DEFAULT} Driver Version:${FG_GREEN}$DRIVER_VERSION ${FG_DEFAULT}\n"
        printf "VBIOS Version:${FG_GREEN} $VBIOS_VERSION ${FG_DEFAULT}\tInfoROM Version:${FG_GREEN} $INFOROM_VERSION ${FG_DEFAULT}\n"
        printf "Dev. ID:${FG_GREEN} $DEVICE_ID ${FG_DEFAULT}SM:${FG_GREEN} $COMPUTING_CORES ${FG_DEFAULT}SlowD.T:${FG_GREEN}$GPU_TEMP_SLOWDOWN${FG_DEFAULT} ShutD.T:${FG_GREEN}$GPU_TEMP_SHUTDOWN${STYLE_OFF}\n"
        printf "Memory Size:${FG_GREEN} $MEMORY_SIZE ${STYLE_OFF}Bus Interface:${FG_GREEN} ${PCI_INFO}${STYLE_OFF}\n"
    
        printf "${FG_LIGHTBLUE}---------------------------| PARAMETERS |--------------------------${STYLE_OFF}\n"
        printf "${REVERSE}G${STYLE_OFF}PU Clock Offset: ${REVERSE}${FG_GREEN}$GPU_CLOCK_OFFSET${STYLE_OFF} \tMin: ${FG_GREEN}$GPU_CLOCK_OFFSET_MIN${STYLE_OFF} \tMax: ${FG_GREEN}$GPU_CLOCK_OFFSET_MAX${STYLE_OFF}  MaxClk: ${FG_GREEN}$GPU_CLOCK_MAX${STYLE_OFF}\n"
        printf "${REVERSE}M${STYLE_OFF}em.Clock Offset: ${REVERSE}${FG_GREEN}$MEMORY_CLOCK_OFFSET${STYLE_OFF} \tMin: ${FG_GREEN}$MEMORY_CLOCK_OFFSET_MIN${STYLE_OFF} \tMax: ${FG_GREEN}$MEMORY_CLOCK_OFFSET_MAX${STYLE_OFF}  MaxClk: ${FG_GREEN}$MEMORY_CLOCK_MAX${STYLE_OFF}\n"
        printf "Core ${REVERSE}V${REVERSE_OFF}.Offset: ${REVERSE}${FG_GREEN}$CORE_VOLTAGE_OFFSET${STYLE_OFF} \tMin: ${FG_GREEN}$CORE_VOLTAGE_MIN_OFFSET${FG_DEFAULT}\tMax: ${FG_GREEN}$CORE_VOLTAGE_MAX_OFFSET${STYLE_OFF} \n"
        if [ "$POWER_MANAGEMENT" == "Enabled" ]; then
            printf "${REVERSE}P${STYLE_OFF}ower Limit: ${REVERSE}${FG_GREEN}$POWER_LIMIT${STYLE_OFF} \tMin: ${FG_GREEN}$POWER_MIN${STYLE_OFF}\tMax: ${FG_GREEN}$POWER_MAX${STYLE_OFF}\n"
        else
            printf "Power Limit: ${FG_GREEN}$POWER_LIMIT${FG_DEFAULT} \tMinimum: ${FG_GREEN}$POWER_MIN${STYLE_OFF}\tMaximum: ${FG_GREEN}$POWER_MAX${STYLE_OFF}\n"
        fi
        if [ $FAN_CONTROL == 0 ]; then
            printf "${REVERSE}F${STYLE_OFF}an Control: ${REVERSE}${FG_GREEN}Disabled${STYLE_OFF}\t                                           \n"
        else
            ENDSTRING='             '
            FANSTR=$FAN_TARGET_SPEED$FAN_CURRENT_SPEED
            printf "${REVERSE}F${STYLE_OFF}an Control: ${REVERSE}${FG_GREEN}Enabled${STYLE_OFF} \t${REVERSE}T${STYLE_OFF}arget Fan PWM: ${REVERSE}${FG_GREEN}$FAN_TARGET_SPEED${STYLE_OFF} Curr. Fan PWM: ${FG_GREEN}$FAN_CURRENT_SPEED${STYLE_OFF}${ENDSTRING:${#FANSTR}}\n"
        fi
        printf "Po${REVERSE}w${REVERSE_OFF}erMizer Mode: ${FG_GREEN}$POWERMIZER_MODE${STYLE_OFF}     Performance State: ${FG_GREEN}$PERFORMANCE_STATE${STYLE_OFF} \n"
        
        LOGGING=$(cat $TMPFILE-logging) # Recover the logging status
        ENDSTRING='---------'  # To make the end of line aligned taking into account the number of samples
        printf "${FG_LIGHTBLUE}----| ${REVERSE}R${REVERSE_OFF}eset Stats/Logs |----| SENSORS |--| ${REVERSE}L${REVERSE_OFF}ogs:$LOGGING |-|N:$SAMPLE_COUNT|${ENDSTRING:${#SAMPLE_COUNT}}${STYLE_OFF}\n"
        printf "GPU Clock: ${FG_GREEN}$GPU_CLOCK${FG_DEFAULT}  \tMax: ${FG_GREEN}$GPU_CLOCK_SMAX${FG_DEFAULT}  \tMin: ${FG_GREEN}$GPU_CLOCK_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.0f  ${STYLE_OFF}\n" $GPU_CLOCK_AVG
        printf "GPU Temp: ${FG_GREEN}$GPU_TEMP${STYLE_OFF}  \tMax: ${FG_GREEN}$GPU_TEMP_SMAX${FG_DEFAULT}  \tMin: ${FG_GREEN}$GPU_TEMP_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.1f  ${STYLE_OFF}\n" $GPU_TEMP_AVG
        printf "Mem.Clock: ${FG_GREEN}$MEMORY_CLOCK${STYLE_OFF}  \tMax: ${FG_GREEN}$MEMORY_CLOCK_SMAX${FG_DEFAULT}  \tMin: ${FG_GREEN}$MEMORY_CLOCK_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.0f  ${STYLE_OFF}\n" $MEMORY_CLOCK_AVG
        printf "Power GPU: ${FG_GREEN}$POWER_GPU  ${STYLE_OFF}  \tMax: ${FG_GREEN}$POWER_GPU_SMAX${FG_DEFAULT}  \tMin: ${FG_GREEN}$POWER_GPU_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.1f  ${STYLE_OFF}\n" $POWER_GPU_AVG
        printf "Fan Speed: ${FG_GREEN}$FAN_CURRENT_SPEED_RPM  ${STYLE_OFF}  \tMax: ${FG_GREEN}$FAN_CURRENT_SPEED_SMAX${FG_DEFAULT}  \tMin: ${FG_GREEN}$FAN_CURRENT_SPEED_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.0f  ${STYLE_OFF}\n" $FAN_CURRENT_SPEED_AVG
        printf "GPU Usage: ${FG_GREEN}$GPU_USAGE  ${STYLE_OFF}  \tMax: ${FG_GREEN}$GPU_USAGE_SMAX${FG_DEFAULT}  \tMin: ${FG_GREEN}$GPU_USAGE_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.0f  ${STYLE_OFF}\n" $GPU_USAGE_AVG
        printf "Memory Usage: ${FG_GREEN}$MEMORY_USAGE  ${STYLE_OFF}  \tMax: ${FG_GREEN}$MEMORY_USAGE_SMAX${FG_DEFAULT}  \tMin: ${FG_GREEN}$MEMORY_USAGE_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.0f  ${STYLE_OFF}\n" $MEMORY_USAGE_AVG
        printf "Core Voltage:${FG_GREEN}$CORE_VOLTAGE${STYLE_OFF}\tMax:${FG_GREEN}$CORE_VOLTAGE_SMAX${FG_DEFAULT}  \tMin:${FG_GREEN}$CORE_VOLTAGE_SMIN${FG_DEFAULT}  \tAvg: ${FG_GREEN}%0.1f  ${STYLE_OFF}\n" $CORE_VOLTAGE_AVG
        printf "${FG_LIGHTBLUE}-------------------------------------------------------------------${STYLE_OFF}\n"
        printf "GPU Throttle:                                                      \r"
        printf "GPU Throttle:${FG_GREEN}$GPU_THROTTLE${STYLE_OFF}\n"
        printf "${FG_LIGHTBLUE}===================================================================${STYLE_OFF}"
    done
}&
DISPLAY_DATA_THREAD_PID=$!

while [ $DISPLAY_DATA -eq 1 ]; do
    #
    # Process keyboard input
    #

    export KEYPRESS=""
    read  -n 1 -s KEYPRESS

    if [ "${KEYPRESS:-}" != "" ]; then
        tput bel
        tput cup 0 0
        printf "${REVERSE}$KEYPRESS${REVERSE_OFF}\r"
        export KEYPRESS
        case $KEYPRESS in
            G)
                graphics_card gpu-clock-offset-set $(( $(graphics_card gpu-clock-offset) + 10 )) > $TMPFILE.log
                ;;
            g)
                graphics_card gpu-clock-offset-set $(( $(graphics_card gpu-clock-offset) - 10 )) > $TMPFILE.log
                ;;
            M)
                graphics_card memory-clock-offset-set $(( $(graphics_card memory-clock-offset) + 50 )) > $TMPFILE.log
                ;;
            m)
                graphics_card memory-clock-offset-set $(( $(graphics_card memory-clock-offset) - 50 )) > $TMPFILE.log
                ;;
            V)
                graphics_card core-voltage-offset-set $(( $(graphics_card core-voltage-offset-raw) + 5000 )) > $TMPFILE.log
                ;;
            v)
                graphics_card core-voltage-offset-set $(( $(graphics_card core-voltage-offset-raw) - 5000 )) > $TMPFILE.log
                ;;
            P)
                graphics_card power-limit-set $(( $(graphics_card power-limit | cut -f1 -d' '| cut -f1 -d'.') + 5 )) > $TMPFILE.log
                ;;
            p)
                graphics_card power-limit-set $(( $(graphics_card power-limit | cut -f1 -d' '| cut -f1 -d'.') - 5 )) > $TMPFILE.log
                ;;
            T)
                if [ $(graphics_card fan-control-get) == 1 ]; then
                    graphics_card fan-target-speed-set $(( $(graphics_card fan-target-speed-get| cut -f1 -d' ') + 1 )) > $TMPFILE.log
                fi
                ;;
            t)
                if [ $(graphics_card fan-control-get) == 1 ]; then
                    graphics_card fan-target-speed-set $(( $(graphics_card fan-target-speed-get| cut -f1 -d' ') - 1 )) > $TMPFILE.log
                fi
                ;;
            f|F)
                if [ $(graphics_card fan-control-get) == 0 ]; then
                    graphics_card fan-control-set > $TMPFILE.log
                else
                    graphics_card fan-control-reset > $TMPFILE.log
                fi
                ;;
            W)
                graphics_card powermizer-mode-set $(( $(graphics_card powermizer-mode-raw) + 1 )) > $TMPFILE.log
                ;;
            w)
                graphics_card powermizer-mode-set $(( $(graphics_card powermizer-mode-raw) - 1 )) > $TMPFILE.log
                ;;
            r|R)
                touch $TMPFILE-reset_sensor_stats
                ;;
            l|L)
                LOGGING=$(cat $TMPFILE-logging) # Recover the logging status
                if [ "$LOGGING" == "OFF" ]; then
                    export LOGGING="ON "
                else
                    export LOGGING="OFF"
                fi
                echo "$LOGGING" > $TMPFILE-logging # Used to share the status across threads
                ;;
        esac
    fi
done

###
#####

# Final clean up
clean_exit
