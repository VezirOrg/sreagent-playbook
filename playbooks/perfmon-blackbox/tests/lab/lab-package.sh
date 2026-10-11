#!/bin/sh
# lab-package.sh: put the package under test (lab pbb-package.env) into the storage account's package container
# (P45 storage mode). dc gets Storage Blob Data Contributor on that container only (lab), downloads the release zip,
# checks its SHA-256 and uploads it unchanged. Prints the container resource ID (the PackageContainerResourceId).
. "$(dirname "$0")/common.sh"
set -eu
cid="$(az storage account show -g "$rg" -n "$sa" --query id -o tsv)/blobServices/default/containers/packages"
dcid=$(az vm show -g "$rg" -n dc --query identity.principalId -o tsv)
az role assignment create --assignee-object-id "$dcid" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$cid" -o none 2>/dev/null || true
sleep 30
guest dc upload-package.ps1 -Url "$PKG_URI" -Sha256 "$PKG_SHA256" -Account "$sa"
echo "PackageContainerResourceId=$cid" | mask
