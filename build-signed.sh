#!/bin/bash
# NeriPlayer 一键构建+签名（服务器 Linux 环境用法见 AGENTS.md）
set -e
cd "$(dirname "$0")/NeriPlayer-HarmonyOS"
export PATH=/opt/command-line-tools/bin:/opt/command-line-tools/tool/node/bin:$PATH
PW=$(cat /home/azureuser/harmony-projects/signing/keystore-password.txt)
hvigorw --no-daemon assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug
java -jar /opt/command-line-tools/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar sign-app \
  -mode localSign -keyAlias harmonyos_debug -signAlg SHA256withECDSA \
  -appCertFile signing/harmonyos_debug.cer -profileFile signing/NeriPlayerDebug.p7b \
  -inFile entry/build/default/outputs/default/entry-default-unsigned.hap \
  -keystoreFile signing/harmonyos_debug.p12 \
  -outFile entry/build/default/outputs/default/entry-default-signed.hap \
  -keyPwd "$PW" -keystorePwd "$PW"
cp entry/build/default/outputs/default/entry-default-signed.hap /home/azureuser/harmony-projects/signing/NeriPlayer-signed.hap
echo "✅ 签名包已生成: NeriPlayer-HarmonyOS/entry/build/default/outputs/default/entry-default-signed.hap"
echo "✅ 下载地址: http://100.73.184.27:8000/NeriPlayer-signed.hap"
