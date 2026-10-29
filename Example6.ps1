$URL_BASE="https://cda.drordas.info"
$DIR_BASE="C:\CDA2627"

function Extraer-ZIP($file, $destination) {
  $shell = new-object -com shell.application
  $zip = $shell.NameSpace($file)
  $shell.NameSpace($destination).copyhere($zip.items())
}


function Preparar-Imagen($nombre_imagen, $url_base_origen, $dir_base_destino) {
  if(!(Test-Path -Path "$dir_base_destino\$nombre_imagen.vdi"))  {
      if(!(Test-Path -Path "$dir_base_destino\$nombre_imagen.vdi.zip"))  {
           Write-Host "Iniciando descarga de $url_base_origen/$nombre_imagen.vdi.zip ..."
           # Invoke-WebRequest "$url_base_origen\$nombre_imagen.vdi.zip"-OutFile "$dir_base_destino\$nombre_imagen.vdi.zip"
           $web_client = New-Object System.Net.WebClient
           $web_client.DownloadFile("$url_base_origen/$nombre_imagen.vdi.zip", "$dir_base_destino/$nombre_imagen.vdi.zip")
      }
      Write-Host "Descomprimiendo $dir_base_destino\$nombre_imagen.vdi.zip ..."
      Extraer-Zip "$dir_base_destino\$nombre_imagen.vdi.zip" "$dir_base_destino"
      Remove-Item "$dir_base_destino\$nombre_imagen.vdi.zip"
  }
}

# ---------------------------------------------------------------------------
# Notas sobre el registro de medios (VirtualBox >= 6)
#
# - Un disco duro solo puede estar en UN registro de medios.
# - El tipo MultiAttach esta prohibido mientras el medio este en el registro
#   GLOBAL (VirtualBox.xml); tiene que estar en el de alguna maquina.
# - Para meterlo en el registro de una maquina hay que engancharlo como normal,
#   desengancharlo y volver a engancharlo con el tipo definitivo. Ni
#   modifymedium ni closemedium: ambos devuelven el medio al registro global.
# - A partir de ahi, CUALQUIER otra maquina que lo quiera debe referenciarlo
#   por UUID. Si se le pasa la ruta del .vdi, VBoxManage lo abre como medio
#   nuevo, cae en el registro global y vuelve el error de MultiAttach.
#
# CDA_NO_BORRAR es la duena estable del registro: hace el rodeo una sola vez y
# se queda los medios enganchados. Las MVs de los ejercicios van por UUID.
# ---------------------------------------------------------------------------


# Devuelve UUID y Tipo del medio registrado en esa ruta, o $null si no lo esta.
# El ancla ^UUID: no casa con "Parent UUID:", que es justo lo que queremos.
function Get-MedioInfo($imagen) {
    $salida = & $script:VBOX_MANAGE list hdds

    $uuid = $null ; $location = $null ; $tipo = $null

    foreach ($linea in $salida) {
        if ($linea -match '^\s*$') {
            if ($location -and ($location -ieq $imagen)) {
                return [pscustomobject]@{ UUID = $uuid ; Tipo = $tipo }
            }
            $uuid = $null ; $location = $null ; $tipo = $null
            continue
        }
        if     ($linea -match '^UUID:\s*(.+?)\s*$')     { $uuid     = $Matches[1] }
        elseif ($linea -match '^Location:\s*(.+?)\s*$') { $location = $Matches[1] }
        elseif ($linea -match '^Type:\s*(.+?)\s*$')     { $tipo     = $Matches[1] }
    }

    if ($location -and ($location -ieq $imagen)) {
        return [pscustomobject]@{ UUID = $uuid ; Tipo = $tipo }
    }
    return $null
}


function Test-MedioRegistrado($imagen, $tipo) {
    $medio = Get-MedioInfo $imagen
    return ($medio -ne $null -and $medio.Tipo -ieq $tipo)
}


# Registra la imagen con el tipo pedido y la deja enganchada a CDA_NO_BORRAR
function Registrar-Imagen($imagen, $tipo, $puerto, $dir_base_destino) {
    $existe = (& $script:VBOX_MANAGE list vms) -match 'CDA_NO_BORRAR'
    if (-not $existe) {
        & $script:VBOX_MANAGE createvm --name CDA_NO_BORRAR --basefolder $dir_base_destino --ostype Debian_64 --register
        & $script:VBOX_MANAGE storagectl CDA_NO_BORRAR --name STORAGE_CDA_NO_BORRAR --add sata --portcount 4
    }

    # Liberar el puerto por si una ejecucion anterior dejo algo colgado
    & $script:VBOX_MANAGE storageattach CDA_NO_BORRAR --storagectl STORAGE_CDA_NO_BORRAR `
        --port $puerto --device 0 --medium none 2>$null

    # 1. Normal: el medio pasa del registro global al de CDA_NO_BORRAR
    & $script:VBOX_MANAGE storageattach CDA_NO_BORRAR --storagectl STORAGE_CDA_NO_BORRAR `
        --port $puerto --device 0 --type hdd --medium $imagen --mtype normal

    # 2. Desenganchar: sigue en el MediaRegistry del .vbox
    & $script:VBOX_MANAGE storageattach CDA_NO_BORRAR --storagectl STORAGE_CDA_NO_BORRAR `
        --port $puerto --device 0 --medium none

    # 3. Ahora si, con el tipo definitivo, y se queda enganchado
    & $script:VBOX_MANAGE storageattach CDA_NO_BORRAR --storagectl STORAGE_CDA_NO_BORRAR `
        --port $puerto --device 0 --type hdd --medium $imagen --mtype $tipo
}


function Registrar-Imagenes($imagen_base, $imagen_swap, $dir_base_destino) {
    if (-not (Test-MedioRegistrado $imagen_base "multiattach")) {
        Registrar-Imagen $imagen_base "multiattach" 0 $dir_base_destino
    }
    if (-not (Test-MedioRegistrado $imagen_swap "immutable")) {
        Registrar-Imagen $imagen_swap "immutable" 1 $dir_base_destino
    }
}


# Comprueba que las imagenes base siguen registradas con el tipo correcto.
# Si se pierde el registro (normalmente por borrar CDA_NO_BORRAR) las MVs ya
# creadas dejan de arrancar y hay que rehacerlas.
function Comprobar-Registro($imagen_base, $imagen_swap) {
    if ((Test-MedioRegistrado $imagen_base "multiattach") -and
        (Test-MedioRegistrado $imagen_swap "immutable")) {
        return
    }

    $mvs = @(& $script:VBOX_MANAGE list vms |
             Where-Object { $_ -match '^"(DATOS|CDA_RAID|DISCOS|CLIENTE|CLIENTE1|CLIENTE2|APACHE1|APACHE2|BALANCEADOR|SERVIDOR1|SERVIDOR2|DENTRO|DMZ|FUERA|FIREWALL3)_' } |
             ForEach-Object { ($_ -split '"')[1] })

    # Sin MVs de ejercicios es una primera ejecucion normal
    if ($mvs.Count -eq 0) { return }

    Write-Host ""
    Write-Host "AVISO: las imagenes base han perdido su registro en VirtualBox."
    Write-Host "       (lo habitual es que se haya borrado la maquina CDA_NO_BORRAR)"
    Write-Host ""
    Write-Host "Estas maquinas dependian de ellas y ya NO van a arrancar:"
    $mvs | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""
    Write-Host "El registro se rehace ahora, pero esas maquinas hay que borrarlas"
    Write-Host "y volver a crearlas con su script:"
    $mvs | ForEach-Object { Write-Host "  VBoxManage unregistervm $_ --delete" }
    Write-Host ""
    $resp = Read-Host "Continuar? [s/N]"
    if ($resp -notmatch '^[sSyY]$') {
        Write-Host "Abortado."
        exit 1
    }
}


# Engancha un medio YA registrado a una MV, por UUID y sin tocar su tipo.
# Nada de --mtype aqui: el medio esta enganchado a CDA_NO_BORRAR y cambiar el
# tipo daria "Cannot change the type ... attached to 1 virtual machines".
function Enganchar-PorUUID($mv, $ctl, $puerto, $imagen) {
    $medio = Get-MedioInfo $imagen
    if ($medio -eq $null) {
        throw "El medio $imagen no esta registrado en VirtualBox"
    }
    $uuid = $medio.UUID
    & $script:VBOX_MANAGE storageattach $mv --storagectl $ctl `
        --port $puerto --device 0 --type hdd --medium $uuid
}

####
####   MAIN
####


if(!(Test-Path -Path $DIR_BASE))  {
   New-Item $DIR_BASE -itemtype directory
}

Preparar-Imagen "swap1GB"  "$URL_BASE" "$DIR_BASE"
Preparar-Imagen "base_cda" "$URL_BASE" "$DIR_BASE"


Write-Host ">> CDA 2026/27 -- Ejemplos de DMZ con Shorewall y VPN con OpenVPN"
$ID = Read-Host "Introducir identificador de las MVs: "



$BASE_VBOX = $env:VBOX_MSI_INSTALL_PATH
if ([string]::IsNullOrEmpty($BASE_VBOX)) {
   $BASE_VBOX = $env:VBOX_INSTALL_PATH
}
if ([string]::IsNullOrEmpty($BASE_VBOX)) {
   $READ_BASE_VBOX = Read-Host ">> Introducir directorio de instalacion de VirtualBox (habitualente `"C:\\Program Files\Oracle\VirtualBox`") :"
   if ([string]::IsNullOrEmpty($READ_BASE_VBOX)) {
      $READ_BASE_VBOX = "`"C:\\Program Files\Oracle\VirtualBox`""
   }
   $BASE_VBOX = $READ_BASE_VBOX
}

$script:VBOX_MANAGE = Join-Path $BASE_VBOX.Trim('"') "VBoxManage.exe"

Write-Host ">> Usando $script:VBOX_MANAGE"

# Rutas canonicas: VirtualBox guarda Location absoluta, y las comparamos literal
$IMAGEN_BASE = (Get-Item -LiteralPath "$DIR_BASE\base_cda.vdi").FullName
$IMAGEN_SWAP = (Get-Item -LiteralPath "$DIR_BASE\swap1GB.vdi").FullName

Comprobar-Registro $IMAGEN_BASE $IMAGEN_SWAP
Registrar-Imagenes $IMAGEN_BASE $IMAGEN_SWAP $DIR_BASE

Write-Host ">> Configurando maquinas virtuales ..."

# Crear imagenes
$MV_DENTRO="DENTRO_$ID"
if (!(Test-Path -Path "$DIR_BASE\$MV_DENTRO"))  {
# Solo 1 vez
  Start-Process $VBOX_MANAGE  "createvm  --name $MV_DENTRO --basefolder `"$DIR_BASE`"  --register --ostype Debian_64 " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "storagectl $MV_DENTRO --name STORAGE_$MV_DENTRO  --add sata --portcount 4" -NoNewWindow -Wait
  Enganchar-PorUUID $MV_DENTRO "STORAGE_$MV_DENTRO" 0 $IMAGEN_BASE
  Enganchar-PorUUID $MV_DENTRO "STORAGE_$MV_DENTRO" 1 $IMAGEN_SWAP
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DENTRO --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vboxsvga" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DENTRO --nic1 intnet --intnet1 vlan1 --macaddress1 080027111111 --cableconnected1 on --nictype1 82540EM " -NoNewWindow -Wait

  Start-Process $VBOX_MANAGE  "modifyvm $MV_DENTRO --nic2 nat  --macaddress2 080027111101 --cableconnected2 on --nictype2 82540EM" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DENTRO --nat-pf2 `"guestssh,tcp,,2225,,22`" " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DENTRO --clipboard-mode bidirectional " -NoNewWindow -Wait


  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/num_interfaces 2" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/eth/0/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/eth/0/address 10.10.10.11" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/eth/0/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/eth/1/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/eth/1/address 10.0.3.15" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/eth/1/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/default_gateway 10.10.10.1" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/host_name dentro.cda.net" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DENTRO /DSBOX/etc_hosts_dump `"dentro.cda.net:10.10.10.11,dmz.cda.net:10.20.20.22,firewall3.cda.net:10.10.10.1,fuera:193.147.87.33`" " -NoNewWindow -Wait
}

$MV_DMZ="DMZ_$ID"
if (!(Test-Path -Path "$DIR_BASE\$MV_DMZ"))  {
# Solo 1 vez
  Start-Process $VBOX_MANAGE  "createvm  --name $MV_DMZ --basefolder `"$DIR_BASE`"  --register --ostype Debian_64 " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "storagectl $MV_DMZ --name STORAGE_$MV_DMZ  --add sata  --portcount 4   " -NoNewWindow -Wait
  Enganchar-PorUUID $MV_DMZ "STORAGE_$MV_DMZ" 0 $IMAGEN_BASE
  Enganchar-PorUUID $MV_DMZ "STORAGE_$MV_DMZ" 1 $IMAGEN_SWAP
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DMZ --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vboxsvga" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DMZ --nic1 intnet --intnet1 vlan2 --macaddress1 080027222222  --cableconnected1 on  --nictype1 82540EM " -NoNewWindow -Wait

  Start-Process $VBOX_MANAGE  "modifyvm $MV_DMZ --nic2 nat  --macaddress2 080027222201 --cableconnected2 on --nictype2 82540EM" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DMZ --nat-pf2 `"guestssh,tcp,,2224,,22`" " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_DMZ --clipboard-mode bidirectional " -NoNewWindow -Wait

  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/num_interfaces 2" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/eth/0/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/eth/0/address 10.20.20.22" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/eth/0/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/eth/1/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/eth/1/address 10.0.3.15" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/eth/1/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/default_gateway 10.20.20.1" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/host_name dmz.cda.net" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_DMZ /DSBOX/etc_hosts_dump `"dmz.cda.net:10.20.20.22,dentro.cda.net:10.10.10.11,firewall3.cda.net:10.20.20.1,fuera:193.147.87.33`" " -NoNewWindow -Wait
}

$MV_FUERA="FUERA_$ID"
if (!(Test-Path -Path "$DIR_BASE\$MV_FUERA"))  {
# Solo 1 vez
  Start-Process $VBOX_MANAGE  "createvm  --name $MV_FUERA --basefolder `"$DIR_BASE`"  --register --ostype Debian_64 " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "storagectl $MV_FUERA --name STORAGE_$MV_FUERA  --add sata  --portcount 4   " -NoNewWindow -Wait
  Enganchar-PorUUID $MV_FUERA "STORAGE_$MV_FUERA" 0 $IMAGEN_BASE
  Enganchar-PorUUID $MV_FUERA "STORAGE_$MV_FUERA" 1 $IMAGEN_SWAP
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FUERA --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vboxsvga" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FUERA --nic1 intnet --intnet1 vlan3 --macaddress1 080027333333  --cableconnected1 on --nictype1 82540EM " -NoNewWindow -Wait

  Start-Process $VBOX_MANAGE  "modifyvm $MV_FUERA --nic2 nat  --macaddress2 080027333301 --cableconnected2 on --nictype2 82540EM" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FUERA --nat-pf2 `"guestssh,tcp,,2222,,22`" " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FUERA --clipboard-mode bidirectional " -NoNewWindow -Wait

  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/num_interfaces 2" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/eth/0/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/eth/0/address 193.147.87.33" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/eth/0/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/eth/1/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/eth/1/address 10.0.3.15" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/eth/1/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/default_gateway 193.147.87.1" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/host_name fuera" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FUERA /DSBOX/etc_hosts_dump `"fuera:193.147.87.33,firewall3.cda.net:193.147.87.47`" " -NoNewWindow -Wait
}

$MV_FIREWALL3="FIREWALL3_$ID"
if (!(Test-Path -Path "$DIR_BASE\$MV_FIREWALL3"))  {
# Solo 1 vez
  Start-Process $VBOX_MANAGE  "createvm  --name $MV_FIREWALL3 --basefolder `"$DIR_BASE`"  --register --ostype Debian_64 " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "storagectl $MV_FIREWALL3 --name STORAGE_$MV_FIREWALL3  --add sata  --portcount 4   " -NoNewWindow -Wait
  Enganchar-PorUUID $MV_FIREWALL3 "STORAGE_$MV_FIREWALL3" 0 $IMAGEN_BASE
  Enganchar-PorUUID $MV_FIREWALL3 "STORAGE_$MV_FIREWALL3" 1 $IMAGEN_SWAP
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FIREWALL3 --cpus 2 --memory 512 --pae on --vram 16 --graphicscontroller vboxsvga" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FIREWALL3 --nic1 intnet --intnet1 vlan1 --macaddress1 080027444444 --cableconnected1 on --nictype1 82540EM " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FIREWALL3 --nic2 intnet --intnet2 vlan2 --macaddress2 080027555555 --cableconnected2 on --nictype2 82540EM " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FIREWALL3 --nic3 intnet --intnet3 vlan3 --macaddress3 080027666666 --cableconnected3 on --nictype3 82540EM " -NoNewWindow -Wait

  Start-Process $VBOX_MANAGE  "modifyvm $MV_FIREWALL3 --nic4 nat  --macaddress4 080027666601 --cableconnected6 on --nictype6 82540EM" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FIREWALL3 --nat-pf4 `"guestssh,tcp,,2223,,22`" " -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "modifyvm $MV_FIREWALL3 --clipboard-mode bidirectional " -NoNewWindow -Wait


  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/num_interfaces 4" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/0/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/0/address 10.10.10.1" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/0/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/1/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/1/address 10.20.20.1" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/1/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/2/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/2/address 193.147.87.47" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/2/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/3/type static" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/3/address 10.0.5.15" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/eth/3/netmask 24" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/default_gateway 193.147.87.1" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/host_name firewall3.cda.net" -NoNewWindow -Wait
  Start-Process $VBOX_MANAGE  "guestproperty set $MV_FIREWALL3 /DSBOX/etc_hosts_dump `"firewall3.cda.net:193.147.87.47,dmz.cda.net:10.20.20.22,dentro.cda.net:10.10.10.11,fuera:193.147.87.33`" " -NoNewWindow -Wait
}

Write-Host ">> Arrancando maquinas virtuales ..."
Start-Process $VBOX_MANAGE  "startvm $MV_DENTRO" -NoNewWindow -Wait
Start-Process $VBOX_MANAGE  "startvm $MV_DMZ" -NoNewWindow -Wait
Start-Process $VBOX_MANAGE  "startvm $MV_FUERA" -NoNewWindow -Wait
Start-Process $VBOX_MANAGE  "startvm $MV_FIREWALL3" -NoNewWindow -Wait

Write-Host ">> Maquinas virtuales arrancadas"

#Start-Process $VBOX_MANAGE  "controlvm  $MV_DENTRO clipboard mode bidirectional" -NoNewWindow -Wait
#Start-Process $VBOX_MANAGE  "controlvm  $MV_DMZ clipboard mode bidirectional" -NoNewWindow -Wait
#Start-Process $VBOX_MANAGE  "controlvm  $MV_FUERA clipboard mode bidirectional" -NoNewWindow -Wait
#Start-Process $VBOX_MANAGE  "controlvm  $MV_FIREWALL3 clipboard mode bidirectional" -NoNewWindow -Wait