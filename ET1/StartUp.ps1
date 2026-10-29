# Script de Automatización del Clúster HPC

$DIR_BASE = "C:\Users\ncado\OneDrive\Escritorio\(Escritorio) Otros\School\3_1 School\CDI\Trabajo1\CDA_Learning_Projects\ET1\vms"
$ID = "HPC"

# 1. Crear directorio base si no existe
if (!(Test-Path -Path $DIR_BASE)) {
    New-Item $DIR_BASE -ItemType Directory | Out-Null
}

# 2. Localizar VBoxManage en el sistema
$BASE_VBOX = $env:VBOX_MSI_INSTALL_PATH
if ([string]::IsNullOrEmpty($BASE_VBOX)) { $BASE_VBOX = $env:VBOX_INSTALL_PATH }
if ([string]::IsNullOrEmpty($BASE_VBOX)) { $BASE_VBOX = "C:\Program Files\Oracle\VirtualBox" }

$script:VBOX_MANAGE = Join-Path $BASE_VBOX.Trim('"') "VBoxManage.exe"

if (!(Test-Path $script:VBOX_MANAGE)) {
    Write-Error "No se encontró VBoxManage.exe en $script:VBOX_MANAGE. Verifica la instalación de VirtualBox."
    exit 1
}

Write-Host ">> Utilizando VirtualBox CLI: $script:VBOX_MANAGE" -ForegroundColor Green

# 3. Definición de la Topología de las MVs (Master, Worker1, Worker2)
$MAQUINAS = @(
    @{
        Nombre   = "master_$ID"
        CPUs     = 2
        RAM      = 2048 # 2 GB
        DiscoGB  = 6
        IP_Red   = "192.168.56.10"
        HostName = "master"
        SSHPort  = 2220
    },
    @{
        Nombre   = "worker1_$ID"
        CPUs     = 1
        RAM      = 1024 # 1 GB
        DiscoGB  = 4
        IP_Red   = "192.168.56.11"
        HostName = "worker1"
        SSHPort  = 2221
    },
    @{
        Nombre   = "worker2_$ID"
        CPUs     = 1
        RAM      = 1024 # 1 GB
        DiscoGB  = 4
        IP_Red   = "192.168.56.12"
        HostName = "worker2"
        SSHPort  = 2222
    }
)

# 4. Creación y Configuración de cada Máquina Virtual
foreach ($mv in $MAQUINAS) {
    $nombre = $mv.Nombre
    $path_mv = "$DIR_BASE\$nombre"

    if (!(Test-Path -Path $path_mv)) {
        Write-Host ">> Creando la máquina virtual: $nombre..." -ForegroundColor Cyan

        # Crear y registrar la MV
        & $script:VBOX_MANAGE createvm --name $nombre --basefolder "$DIR_BASE" --register --ostype "Linux_64"

        # Configurar CPU, RAM, Gráficos y Portapapeles
        & $script:VBOX_MANAGE modifyvm $nombre --cpus $mv.CPUs --memory $mv.RAM --vram 16 --graphicscontroller vboxsvga --clipboard-mode bidirectional

        # Configuración de Red:
        # NIC 1: Red Interna (Comunicación entre nodos Slurm/MPI)
        & $script:VBOX_MANAGE modifyvm $nombre --nic1 intnet --intnet1 "hpc_net" --nictype1 82540EM --cableconnected1 on

        # NIC 2: NAT (Acceso a Internet y puerto SSH hacia Windows)
        & $script:VBOX_MANAGE modifyvm $nombre --nic2 nat --nictype2 82540EM --cableconnected2 on
        & $script:VBOX_MANAGE modifyvm $nombre --nat-pf2 "guestssh,tcp,,$($mv.SSHPort),,22"

        # Crear y asociar Disco Duro VDI
        $disco_path = "$path_mv\$nombre.vdi"
        $size_mb = $mv.DiscoGB * 1024
        & $script:VBOX_MANAGE createmedium disk --filename "$disco_path" --size $size_mb --format VDI
        & $script:VBOX_MANAGE storagectl $nombre --name "STORAGE_$nombre" --add sata --portcount 2
        & $script:VBOX_MANAGE storageattach $nombre --storagectl "STORAGE_$nombre" --port 0 --device 0 --type hdd --medium "$disco_path"

        # Inyectar propiedades de Guest (Para que los scripts de arranque lean IP y Hostname)
        & $script:VBOX_MANAGE guestproperty set $nombre /HPC/ip $mv.IP_Red
        & $script:VBOX_MANAGE guestproperty set $nombre /HPC/hostname $mv.HostName
        & $script:VBOX_MANAGE guestproperty set $nombre /HPC/etc_hosts "192.168.56.10 master`n192.168.56.11 worker1`n192.168.56.12 worker2"

        Write-Host "   -> MV $nombre configurada (RAM: $($mv.RAM)MB, Disco: $($mv.DiscoGB)GB, IP: $($mv.IP_Red), Puerto SSH: $($mv.SSHPort))" -ForegroundColor Yellow
    } else {
        Write-Host ">> La máquina virtual $nombre ya existe. Omitiendo creación." -ForegroundColor Gray
    }
}

# 5. Arrancar Máquinas Virtuales
Write-Host "`n>> Deseas arrancar las 3 Máquinas Virtuales ahora? [S/N]" -ForegroundColor Green
$resp = Read-Host
if ($resp -match '^[sSyY]$') {
    foreach ($mv in $MAQUINAS) {
        Write-Host ">> Arrancando $($mv.Nombre)..."
        & $script:VBOX_MANAGE startvm $mv.Nombre
    }
}   