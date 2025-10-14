#!/bin/bash

#SBATCH -N 1 # Number of nodes. You must always set -N 1 unless you receive special instruction from the system admin
#SBATCH -n 1 # Number of tasks. Don't specify more than 16 unless approved by the system admin
#SBATCH --mail-type=ALL # Type of email notification- BEGIN,END,FAIL,ALL. Equivalent to the -m option in SGE
#SBATCH --mail-user=luised94@mit.edu  # Email to which notifications will be sent. Equivalent to the -M option in SGE.
#SBATCH --exclude=c[5-22]
#SBATCH --mem-per-cpu=20G # amount of RAM per node#
#DESCRIPTION: <brief_description_of_purpose>
#USAGE: <usage_instructions>

# Function to <function_purpose>
# Parameters:
#   $1: <param1_description>
#   $2: <param2_description>
# Returns:
#   <return_description>
function_name() {
    local param1=$1
    local param2=$2
    
    # Function implementation
    
    # Return value
    echo <return_value>
}

# Main script logic
# Description of the main code block's purpose

# Example of calling the function
# result=$(function_name arg1 arg2)

# Add your main script logic here
