
<div class="no-overflow" id="yui_3_18_1_1_1793286695628_135"><div style="max-width: 940px; margin: 0 auto; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; font-size: 16px; line-height: 1.6; color: #4f4f4f; background: #ffffff; box-sizing: border-box;" id="yui_3_18_1_1_1793286695628_134">

  <!-- Portada -->
  <header style="background: #202729; color: #ffffff; padding: 40px 24px 28px; border-radius: 4px 4px 0 0;" id="yui_3_18_1_1_1793286695628_133">
    <h1 style="font-weight: 400; font-size: 2.2rem; line-height: 1.1; margin: 0; padding-bottom: 14px; border-bottom: 1px solid #5d6668; color: #ffffff;"><span style="color: #63d297; font-weight: 700;">C</span>entros de <span style="color: #63d297; font-weight: 700;">D</span>atos</h1>
    <p style="font-size: 1.3rem; color: #63d297; margin: 12px 0 6px; font-weight: 600;">Trabajos grupales</p>
    <p style="margin: 0; color: #e7ecea; font-size: 0.95rem;"> Vee <span style="color: #9fb0aa;">·</span> Sergio Creo</p>
  </header>

</div></div>

<article id="t11" style="background: #ffffff; border: 1px solid #e2e6e4; border-bottom: 6px solid #63d297; border-radius: 4px; padding: 22px 24px; margin-bottom: 24px; box-shadow: 0 1px 3px rgba(0,0,0,0.05);">
      <div style="display: flex; gap: 12px; align-items: flex-start; padding-bottom: 10px; border-bottom: 2px solid #4ba173;">
        <span style="font-weight: 700; font-size: 0.95rem; color: #ffffff; background: #4ba173; border-radius: 4px; padding: 4px 8px;">11</span>
        <h2 style="font-weight: 700; color: #4ba173; margin: 0; font-size: 1.35rem; line-height: 1.25;">Clúster de computación de altas prestaciones (HPC) con Slurm y MPI</h2>
      </div>
      <span style="display: inline-block; margin-top: 12px; font-size: 0.82rem; font-weight: 600; background: #202729; color: #63d297; border-radius: 4px; padding: 4px 8px;">Límite: 3 personas</span>
      <h3 style="margin: 16px 0 6px; font-size: 0.82rem; font-weight: 700; text-transform: uppercase; color: #2b3133;">Descripción</h3>
      <p style="margin: 0;">Configurar un clúster HPC con nodo gestor y nodos de cómputo gestionados por Slurm.</p>
      <h3 style="margin: 16px 0 6px; font-size: 0.82rem; font-weight: 700; text-transform: uppercase; color: #2b3133;">Requisitos</h3>
      <ol style="margin: 0; padding-left: 1.4em;">
        <li>Introducción a HPC, gestores de colas y paralelismo con MPI.</li>
        <li>Desplegar al menos 3 MVs con Munge, sincronización horaria y `/home` vía NFS.</li>
        <li>Configuración de particiones y envío de tareas con <code>sbatch</code> y <code>srun</code>.</li>
        <li>Ejecución de un programa paralelo OpenMPI comparando tiempos.</li>
      </ol>
      <div style="margin-top: 16px; background: #eef8f2; border-left: 4px solid #63d297; border-radius: 4px; padding: 12px 16px;">
        <h3 style="margin: 0 0 6px; color: #3d8a61; font-size: 0.82rem; font-weight: 700; text-transform: uppercase;">Notas</h3>
        <ul style="margin: 0; padding-left: 1.4em;">
          <li>Todos los nodos deben tener idéntica versión de Slurm, mismos UID/GID y relojes sincronizados para que Munge no rechace credenciales.</li>
        </ul>
      </div>
    </article>