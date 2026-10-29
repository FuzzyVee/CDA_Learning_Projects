# Guía Práctica de Kubernetes desde Cero: Despliegue de un Clúster con Kubeadm

Kubernetes es la plataforma estándar para la orquestación y automatización de aplicaciones en contenedores a gran escala. Esta guía está diseñada para acompañar paso a paso a quienes se inician en la administración de clústeres, ofreciendo una ruta clara para comprender la arquitectura subyacente y desplegar un entorno funcional de tres nodos utilizando la herramienta oficial `kubeadm`.

---

## 1. Contextualización y Arquitectura Fundamental de Kubernetes

Antes de ejecutar cualquier comando de instalación, es esencial comprender cómo se organizan los componentes de un clúster de Kubernetes y cuál es la función de cada uno.

### El Modelo Control Plane y Nodos Worker

Un clúster de Kubernetes se divide en dos tipos de nodos principales:

| Tipo de Nodo | Rol Principal | Componentes Clave |
| :--- | :--- | :--- |
| **Control Plane (Nodo Principal)** | Gestiona el estado del clúster, toma decisiones de planificación y responde a eventos. | `kube-apiserver`, `etcd`, `kube-scheduler`, `kube-controller-manager` |
| **Worker (Nodo de Cómputo)** | Mantiene los contenedores en ejecución y proporciona los recursos de cómputo. | `kubelet`, `kube-proxy`, Runtime de Contenedores (ej. `containerd`) |

* **`kube-apiserver`**: La puerta de entrada al clúster. Todas las órdenes de administración (vía `kubectl`) pasan por esta API.
* **`etcd`**: Base de datos clave-valor distribuida donde se almacena todo el estado y configuración del clúster.
* **`kube-scheduler`**: Asigna los contenedores recién creados a los nodos con recursos disponibles.
* **`kubelet`**: El agente que se ejecuta en cada nodo worker para asegurar que los contenedores se ejecuten correctamente según las instrucciones del nodo principal.

### Unidades de Despliegue Básicas

En Kubernetes no se despliegan contenedores directamente de forma individual, sino abstraídos en objetos:

* **Pod**: La unidad mínima ejecutable. Contiene uno o más contenedores estrechamente vinculados que comparten red y almacenamiento.
* **Deployment**: Objeto que gestiona la creación, actualización y escalado declarativo de un grupo de Pods idénticos.
* **Service**: Expone un conjunto de Pods bajo una dirección IP o puerto estable, realizando balanceo de carga interno.

---

## 2. Preparación de la Infraestructura y Requisitos Previos

Para implementar el clúster de tres nodos (1 Control Plane y 2 Workers), se requieren 3 Máquinas Virtuales con un sistema Linux basado en Debian o Ubuntu.

### Requisitos Mínimos por Nodo

* **Nodo Control Plane**: Mínimo 2 vCPUs y 2 GB de memoria RAM.
* **Nodos Workers (2 MVs)**: 1 vCPU y 1–2 GB de memoria RAM por nodo.
* **Conectividad de red**: Direcciones IP estáticas en la misma subred privada (ejemplo: `192.168.56.10` para el Control Plane, `192.168.56.11` para worker1 y `192.168.56.12` para worker2).

### Paso 1: Desactivar la Memoria Swap (Obligatorio)

Kubernetes exige que la memoria swap esté completamente desactivada en todos los nodos. La presencia de memoria de intercambio interfiere con el cálculo preciso de límites de memoria que realiza `kubelet` para garantizar el rendimiento.

Ejecutar en los **tres nodos**:

```bash
# Desactivar la memoria swap de forma inmediata
sudo swapoff -a

# Comentar la línea de swap en /etc/fstab para hacerlo permanente
sudo sed -i '/swap/s/^/#/' /etc/fstab
```

### Paso 2: Cargar Módulos del Núcleo y Ajustar Parámetros de Red

Kubernetes requiere que los módulos de red del kernel estén habilitados para el filtrado de paquetes en puentes de red:

```bash
# Cargar módulos necesarios
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configurar parámetros sysctl para red
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

---

## 3. Instalación de Herramientas de Kubernetes y Runtimes

En este bloque se instalan el motor de contenedores (`containerd`) y las utilidades propias de Kubernetes en las tres máquinas virtuales.

### Paso 1: Instalar y Configurar `containerd`

En los **tres nodos**:

```bash
sudo apt-get update
sudo apt-get install -y containerd

# Generar la configuración por defecto y habilitar el driver cgroup de systemd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Paso 2: Instalar `kubeadm`, `kubelet` y `kubectl`

Añadir los repositorios oficiales e instalar los componentes esenciales:

1. **`kubeadm`**: La herramienta para inicializar y unir nodos al clúster.
2. **`kubelet`**: El servicio en segundo plano que gestiona los Pods en cada nodo.
3. **`kubectl`**: La CLI para enviar comandos de administración al clúster.

En los **tres nodos**:

```bash
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gnupg

# Configurar el repositorio oficial e instalar paquetes
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

---

## 4. Inicialización del Clúster y Despliegue de la Red CNI

Una vez instaladas las dependencias en todas las máquinas, se procede al arranque del nodo Control Plane y a la asociación de los nodos workers.

### Paso 1: Inicializar el Nodo Control Plane

Ejecutar **únicamente en el nodo Control Plane** (`192.168.56.10`):

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.56.10
```

Para empezar a administrar el clúster con `kubectl` desde el usuario no-root:

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Paso 2: Unir los Nodos Worker al Clúster

En cada uno de los **nodos worker** (`worker1` y `worker2`), ejecutar el comando `kubeadm join` proporcionado al final de la salida del nodo Control Plane:

```bash
sudo kubeadm join 192.168.56.10:6443 --token <TOKEN_ASIGNADO> \
    --discovery-token-ca-cert-hash sha256:<HASH_DEL_CERTIFICADO>
```

Si ejecutas `kubectl get nodes` en el Control Plane en este punto, verás los tres nodos listados pero en estado `NotReady`. Esto ocurre porque aún falta instalar la red CNI.

### Paso 3: Desplegar la Interfaz de Red de Contenedores (CNI: Flannel o Calico)

Sin un complemento CNI (*Container Network Interface*), los Pods no pueden asignarse direcciones IP internas ni comunicarse entre sí.

Para desplegar el Manifiesto CNI (por ejemplo, **Flannel**):

Ejecutar **únicamente en el nodo Control Plane**:

```bash
kubectl apply -f kube-flannel.yml
```

*(Si prefieres usar Calico, puedes aplicar su manifiesto YAML correspondiente)*.

Esperar unos segundos y verificar nuevamente los nodos:

```bash
kubectl get nodes
```

**Resultado esperado:**
Los tres nodos (`control-plane`, `worker1`, `worker2`) deben pasar al estado **`Ready`**.

---

## 5. Despliegue de Aplicaciones, Escalado Horizontal y Prueba de Tolerancia a Fallos

Con el clúster plenamente operativo, se realiza la verificación funcional desplegando una aplicación web ligera y analizando el comportamiento del sistema ante demandas de carga y caídas de nodos.

### Paso 1: Desplegar una Aplicación NGINX

Crear un *Deployment* con dos réplicas iniciales de NGINX:

```bash
kubectl create deployment nginx-demo --image=nginx:alpine --replicas=2
```

Exponer la aplicación mediante un Servicio de tipo *NodePort* para acceder desde el exterior:

```bash
kubectl expose deployment nginx-demo --port=80 --type=NodePort
```

Verificar la distribución de los Pods y el puerto asignado:

```bash
kubectl get pods -o wide
kubectl get services nginx-demo
```

---

### Paso 2: Verificación del Escalado Horizontal

Para escalar la aplicación de 2 a 5 réplicas:

```bash
kubectl scale deployment nginx-demo --replicas=5
```

Verificar el resultado inmediatamente:

```bash
kubectl get pods -o wide
```

Se observará cómo Kubernetes distribuye automáticamente los 5 Pods entre los nodos de cómputo disponibles (`worker1` y `worker2`).

---

### Paso 3: Verificación de Tolerancia a Fallos (Self-Healing)

Kubernetes monitoriza constantemente el estado deseado frente al estado real. Si un nodo o Pod falla, el sistema reprograma los contenedores en nodos saludables.

#### Prueba A: Eliminación Manual de un Pod
Eliminar uno de los Pods activos:

```bash
kubectl delete pod <NOMBRE_DE_UN_POD>
```

Al consultar `kubectl get pods`, se comprobará que Kubernetes ha detectado la discrepancia en el número de réplicas y ha creado instantáneamente un nuevo Pod de reemplazo.

#### Prueba B: Caída o Apagado de un Nodo Worker
Simular una avería apagando la máquina virtual `worker1`.

1. Apagar la MV `worker1`.
2. Monitorizar el estado en el nodo Control Plane:
   ```bash
   kubectl get nodes -w
   ```
3. Pasado el tiempo de tolerancia (*eviction timeout*), el nodo figurará como `NotReady` y Kubernetes reprogramará automáticamente los Pods que estaban en `worker1` para que pasen a ejecutarse en `worker2`.

---

## 6. Hoja de Referencia: Comandos Básicos de `kubectl`

| Categoría | Comando | Descripción |
| :--- | :--- | :--- |
| **Estado del Clúster** | `kubectl get nodes` | Muestra el estado y rol de todos los nodos del clúster. |
| **Consulta de Pods** | `kubectl get pods -A` | Lista todos los Pods en todos los *namespaces*. |
| **Detalles y Logs** | `kubectl describe pod <nombre>` | Muestra eventos y diagnósticos detallados sobre un Pod. |
| | `kubectl logs <nombre>` | Muestra la salida estándar de los contenedores de un Pod. |
| **Gestión** | `kubectl apply -f archivo.yaml` | Crea o actualiza recursos de forma declarativa. |
| | `kubectl scale deployment <nombre> --replicas=N` | Modifica el número de réplicas en ejecución. |
| | `kubectl delete pod <nombre>` | Elimina un Pod (útil para probar reprogramación). |

---

## Lista de Verificación Final para el Trabajo

- [ ] Tres MVs creadas y comunicadas en red privada (1 Control Plane, 2 Workers).
- [ ] Memoria swap desactivada permanentemente en los tres nodos.
- [ ] Módulos del kernel `overlay` y `br_netfilter` cargados y `ip_forward` activo.
- [ ] Runtime `containerd` configurado con `SystemdCgroup = true`.
- [ ] Clúster inicializado con `kubeadm init` y token aplicado en nodos worker.
- [ ] Red CNI (Flannel o Calico) desplegada y todos los nodos en estado `Ready`.
- [ ] Aplicación desplegada, escalada con `kubectl scale` y probada ante fallos de Pods y nodos.
