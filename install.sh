#!/usr/bin/env bash

rm -rf ASCFrameworkProject
rm -rf temp_project

echo "Framework-下载工程文件模版"
git clone -b main git@github.com:blackteachinese/iOSDynamicFramework.git ASCFrameworkProject

echo "Framework-拷贝工程模版"
mv ASCFrameworkProject/template temp_project

echo "Framework-执行ruby脚本"

cd ASCFrameworkProject
bundle install
cd ..
ruby ASCFrameworkProject/generateFrameworkProject.rb

echo "Framework-完成"

ls