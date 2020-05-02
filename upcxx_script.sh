#!/bin/bash

#Set Script Name variable
SCRIPT=`basename ${0}`

# Default variables for the build and run
debug="Release"
num_nodes="1"
num_proc="32"
test_file="test"
test_output=""
verbose=""
run_time="10"

#Set fonts for Help.
NORM=`tput sgr0`
BOLD=`tput bold`
REV=`tput smso`

# Print function for usage help information
print_usage() {
  echo
  echo -e "${BOLD}Help description to build and run the UPC++ EECS267 HW3 on Cori KNL nodes${BOLD}\n"
  echo -e "${REV}Usage:${NORM} ${SCRIPT} [-h] [-d] [-N <1-9,668>] [-n <1-68>] 
        [-f <human|test|small|little|verysmall|tiny>] [-o | -v] [-t <10-300>]\n"
  echo -e "${REV}-h${NORM} show this help message"
  echo -e "${REV}-d${NORM} build the cmake project with -DCMAKE_BUILD_TYPE=Debug, default is Release"
  echo -e "${REV}-N${NORM} number of nodes to run the binary kmer_hash on, default is N=1"
  echo -e "${REV}-n${NORM} number of processors to run the binary kmer_hash on, default is n=32"
  echo -e "${REV}-f${NORM} dataset to run the binary kmer_hash on, default is test (make sure my_datasets is inside build dir)"
  echo -e "${REV}-o${NORM} generate test output for correctness (mutually exclusive with -v flag), default is false"
  echo -e "${REV}-v${NORM} run in verbose mode (mutually exclusive with -o flag), default is false"
  echo -e "${REV}-t${NORM} running time in minutes for interactive session if called from login node, default is 10 minutes\n"
  echo -e "Example (release build, run verbosely on 2 nodes and 10 processes on the human-chr14-synthetic.txt dataset):"
  echo -e "${BOLD}${SCRIPT} -N 2 -n 10 -f human -v${BOLD}\n"
  exit 1
}

# Handle the flags
while getopts :hdN:n:f:ovt: flag; do
  case ${flag} in
    h) print_usage;;
    d) debug="Debug" ;;
    N) num_nodes="${OPTARG}" ;;
    n) num_proc="${OPTARG}" ;;
    f) test_file="${OPTARG}" ;;
    o) [ -n "${verbose}" ] &&
       echo -e "\nOptions ${BOLD}-v${BOLD} and ${BOLD}-o${BOLD} not allowed together.\n" &&
       exit 1 || test_output="test" ;;
    v) [ -n "${test_output}" ] &&
       echo -e "\nOptions ${BOLD}-o${BOLD} and ${BOLD}-v${BOLD} not allowed together.\n" &&
       exit 1 || verbose="verbose" ;;
    t) run_time="${OPTARG}" ;;  
    \?) echo "Option ${BOLD}-${OPTARG}${BOLD} not allowed."; print_usage ;;
  esac
done

# Username for the project dir
user_name=`whoami`

# Build directory
build_dir="/global/cscratch1/sd/${user_name}/hw3/build/"

# CMake directory
cmake_dir=`dirname ${build_dir}`

# Go to the final project build directory
cd ${build_dir}

# Test output directory
out_dir="${build_dir}test_output/"

# Check if running on an interactive session with KNL processors.
knl_check=`head /proc/cpuinfo | grep -o "Xeon Phi"`

# Show build and run options
echo -e "${REV}Configuration:"${NORM}
echo -e "${BOLD}-DCMAKE_BUILD_TYPE=${debug}${NORM}"
echo -e "${BOLD}Number of Nodes = ${num_nodes}${NORM}"
echo -e "${BOLD}Number of Processors = ${num_proc}${NORM}"
if [ "${test_file}" = "human" ]
then
  echo -e "${BOLD}Dataset = human-chr14-synthetic.txt"
  dkmerlen_flag="-DKMER_LEN=51"
  echo -e "${BOLD}${dkmerlen_flag}"
else
  echo -e "${BOLD}Dataset = ${test_file}.txt"
  dkmerlen_flag="-DKMER_LEN=19"
  echo -e "${BOLD}${dkmerlen_flag}"
fi
if [ -n "${test_output}" ]
then
  echo -e "${BOLD}Test Output = True${NORM}"
fi
if [ -n "${verbose}" ]
then
  echo -e "${BOLD}Verbose = True${NORM}"
fi
if [ -z "${knl_check}" ]
then
  echo -e "${BOLD}Interactive Session Running Time = ${run_time} minutes${NORM}"
fi
echo -e "${BOLD}-----------------------------------------------${BOLD}"

# Create build and test output directory if they don't exist 
if [ ! -d ${build_dir} ]
then
  mkdir ${build_dir}
fi
if [ ! -d ${out_dir} ]
then
  mkdir ${out_dir}    
else
  # Check if there are any pre-existing test output files and delete them
  test_datfile=`ls ${out_dir} | grep "test*.dat"`
  if [ -n "${test_datfile}" ]
  then
    rm ${out_dir}test*.dat  
  fi
fi

# Load all of the relevant modules in module.sh
prgenv_module=`module list |& grep -o "PrgEnv.*"`
craype_module=`module list |& grep -o "craype-haswell"`
upcxx_module=`module list |& grep -o "upcxx"`
cmake_module=`module list |& grep -o "cmake"`

if [ "${prgenv_module}" != "PrgEnv-cray" ]
then
  module swap ${prgenv_module} PrgEnv-cray
fi
if [ -n "${craype_module}" ]
then
  module unload craype-haswell
  module load craype-mic-knl
fi
if [ -z "${upcxx_module}" ]
then
  module load upcxx
fi
if [ -z "${cmake_module}" ]
then
  module load cmake
fi

# Build the makefiles and create a binary while suppressing output to avoid clutter
echo
echo -e "${BOLD}Building ${debug} version...${BOLD}"
cmake -DCMAKE_BUILD_TYPE=${debug} -DCMAKE_CXX_COMPILER=CC $dkmerlen_flag ${cmake_dir} >& /dev/null
echo -e "${BOLD}Build complete.${BOLD}"
echo -e "${BOLD}Creating binaries...${BOLD}"
cmake --build ${build_dir} >& /dev/null
echo -e "${BOLD}kmer_hash binary built on ${build_dir}${BOLD}\n"


# Check the dataset selected
dataset_check=`echo "${test_file}" | grep "test"`
dataset_check_human=`echo "${test_file}" | grep "human"`

if [ "${dataset_check}" = "test" ]
then
  dataset_var="${build_dir}my_datasets/test.txt"
elif [ -n "${dataset_check_human}" ]
then
  dataset_var="${build_dir}my_datasets/human-chr14-synthetic.txt"
else
  dataset_var="${build_dir}my_datasets/smaller/${test_file}.txt"
fi

# Check that the dataset is valid
if [ ! -f "${dataset_var}" ]
then
  echo -e "${BOLD}File ${dataset_var} does not exist.${BOLD}\n"
  exit 0
fi

# Run from the test output directory
cd ${out_dir}

# Run the binary on an interactive session if not on one already
if [ -z "${knl_check}" ]
then
  echo -e "${BOLD}Requesting Interactive KNL Session for ${run_time} minutes...${BOLD}"
  salloc -N ${num_nodes} -A mp309 -t ${run_time} -q debug --qos=interactive -C knl \
srun -N ${num_nodes} -n ${num_proc} ${build_dir}kmer_hash ${dataset_var} ${verbose} ${test_output} || exit 0
else
  echo -e "${BOLD}Running on current Interactive KNL Session...${BOLD}"
  srun -N ${num_nodes} -n ${num_proc} ${build_dir}kmer_hash ${dataset_var} ${verbose} ${test_output} || exit 0
fi

if [ -n "${test_output}" ]
then
  my_solution_file="${test_file}_my_solution.txt"
  ref_solution_file=`echo ${dataset_var} | sed -E 's/(.+).txt/\1_solution.txt/g'`
  echo
  echo -e "${BOLD}Collecting and generating output solution ${my_solution_file}...${BOLD}"
  cat test*.dat  | sort > ${my_solution_file}
  echo -e "${BOLD}Comparing ${my_solution_file} with reference solution ${ref_solution_file}${BOLD}\n"
  diff_check=`diff ${my_solution_file} ${ref_solution_file}`
  if [ -z "${diff_check}" ]
  then
    echo -e "${REV}${BOLD}Comparison Passed${NORM}\n"
  else
    echo -e "${REV}${BOLD}Comparison Failed${NORM}\n"
  fi
  echo -e "${BOLD}Removing the generated .dat files${BOLD}"
  rm test*.dat
fi
