# Memoria ET1 Logica de Computacion.



<div style="text-align: right; margin-bottom: 12px;">
  <span style="font-size: 0.75em; background: #e0e0e0; color: #333; padding: 2px 8px; border-radius: 10px; font-weight: bold;">
     2026-10-29
  </span>
</div>
</div>

---

### 📋 Checklist de Despliegue de Kubernetes (`kubeadm`)

#### **Fase 1: Preparación del Entorno de MVs**

* [ ] **Crear las 3 Máquinas Virtuales** (`master`, `worker1`, `worker2`).
* [ ] **Asignar recursos suficientes**: Mínimo 2 vCPUs y 2 GB RAM para `master`; 1-2 vCPUs y 1.5-2 GB RAM para cada `worker`.
* [ ] **Configurar las interfaces de red**: IP estática en red privada/host-only y acceso a Internet.
* [ ] **Configurar hostnames únicos**: `hostnamectl set-hostname master`, `worker1`, `worker2`.
* [ ] **Configurar resolución DNS local**: Añadir las IPs y nombres de los 3 nodos en `/etc/hosts` de todas las MVs.

---

#### **Fase 2: Configuración Base del Sistema (En TODOS los nodos)**

* [ ] **Desactivar la memoria Swap**:
  * [ ] Ejecutar `sudo swapoff -a`.
  * [ ] Comentar la línea de `swap` en `/etc/fstab` para hacerlo permanente.
* [ ] **Cargar módulos del Kernel necesarios**:
  * [ ] Habilitar `overlay` y `br_netfilter` (`modprobe`).
* [ ] **Ajustar parámetros de red** **sysctl**:
  * [ ] Habilitar `net.bridge.bridge-nf-call-iptables = 1`.
  * [ ] Habilitar `net.ipv4.ip_forward = 1`.
* [ ] **Instalar y configurar el ejecutable de contenedores (** **containerd** **)**:
  * [ ] Instalar `containerd`.
  * [ ] Generar configuración por defecto (`containerd config default`).
  * [ ] Activar el driver de cgroup de systemd (`SystemdCgroup = true`).
  * [ ] Reiniciar y habilitar el servicio `containerd`.
* [ ] **Instalar herramientas de Kubernetes**:
  * [ ] Añadir el repositorio oficial de Kubernetes.
  * [ ] Instalar `kubelet`, `kubeadm` y `kubectl`.
  * [ ] Marcar paquetes para evitar actualizaciones automáticas (`apt-mark hold`).

---

#### **Fase 3: Inicialización del Control Plane (Solo en** **master** **)**

* [ ] **Ejecutar** **kubeadm init**: Especificar `--pod-network-cidr=10.244.0.0/16` y `--apiserver-advertise-address=<IP_MASTER>`.
* [ ] **Configurar credenciales de administración (** **kubectl** **)**:
  * [ ] Copiar `/etc/kubernetes/admin.conf` a `$HOME/.kube/config`.
  * [ ] Asignar permisos al usuario no-root.
* [ ] **Guardar el token de unión**: Copiar y guardar el comando `kubeadm join ...` generado al final.

---

#### **Fase 4: Red de Pods / CNI (Solo desde** **master** **)**

* [ ] **Desplegar el plugin CNI** (por ejemplo, Flannel): `kubectl apply -f [suspicious link removed]`.
* [ ] **Verificar estado del nodo** **master**: Comprobar con `kubectl get nodes` que pasa a estado `Ready`.
* [ ] **Verificar Pods de sistema**: Comprobar con `kubectl get pods -n kube-system` que CoreDNS y los componentes están en `Running`.

---

#### **Fase 5: Unir los Nodos Trabajadores**

* [ ] **Unir** **worker1**: Ejecutar el comando `kubeadm join` guardado previamente.
* [ ] **Unir** **worker2**: Ejecutar el comando `kubeadm join` guardado previamente.
* [ ] **Verificar el clúster completo**: Desde el `master`, ejecutar `kubectl get nodes` y confirmar que los 3 nodos están en estado `Ready`.

---

#### **Fase 6: Pruebas de Aplicación, Escalado y Tolerancia a Fallos**

* [ ] **Desplegar una aplicación de prueba**: `kubectl create deployment nginx-demo --image=nginx`.
* [ ] **Exponer el servicio**: `kubectl expose deployment nginx-demo --type=NodePort --port=80`.
* [ ] **Comprobar acceso**: Acceder a la web desde el navegador usando la IP de cualquier nodo y el puerto asignado (`NodePort`).
* [ ] **Probar escalado horizontal**: Aumentar réplicas a 4 (`kubectl scale deployment nginx-demo --replicas=4`) y verificar distribución con `kubectl get pods -o wide`.
* [ ] **Simular fallo de nodo**: Apagar `worker1` (`shutdown -h now`) y comprobar cómo Kubernetes reprograma automáticamente los Pods afectados hacia `worker2`.