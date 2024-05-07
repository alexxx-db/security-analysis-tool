#/bin/bash

project=$1
profile=$2
config_file=$3


cp -r ../configs ../notebooks ../dashboards ./dabs_template/template/tmp
rm ./dabs_template/template/tmp/notebooks/Utils/initialize.py
cp ./dabs_template/initialize.py.tmpl ./dabs_template/template/tmp/notebooks/Utils/initialize.py.tmpl

databricks bundle init ./dabs_template -p $profile --config-file $config_file
rm -rf $config_file
cd $project
databricks bundle deploy -p $profile --force-lock
cd ../
rm -rf $project
rm -rf configs dashboards notebooks

