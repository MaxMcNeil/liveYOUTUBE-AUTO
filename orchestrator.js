/**
 * Orchestrateur de rotation de contenu pour livestream autonome.
 *
 * Principe de détection de fin de boucle :
 * Comme chaque site tourne en boucle infinie avec une durée variable d'un
 * passage à l'autre, on ne peut pas se fier à un minutage fixe. On prend
 * donc une "empreinte" (hash du texte visible) du contenu à intervalles
 * réguliers. Une fois la durée minimale (minLoopMs) écoulée, on fige une
 * empreinte de référence. Si cette même empreinte réapparaît plusieurs
 * fois de suite (stableRepeatsToConfirm), on considère que la boucle a
 * bouclé et on bascule vers le site suivant. Un garde-fou (maxLoopMs)
 * force le passage au site suivant même si la détection échoue, pour ne
 * jamais rester bloqué indéfiniment sur un site.
 *
 * Ce script pilote une page Chromium persistante (celle-là même que
 * ffmpeg capture via x11grab sur le display Xvfb). Il ne lance pas
 * ffmpeg lui-même : voir start_stream.sh.
 */

const { chromium } = require('playwright');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const CONFIG_PATH = path.join(__dirname, 'config.json');

function loadConfig() {
  return JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf-8'));
}

function hashText(text) {
  return crypto.createHash('sha1').update(text || '').digest('hex');
}

function readControl(controlFile) {
  try {
    return JSON.parse(fs.readFileSync(controlFile, 'utf-8'));
  } catch {
    return { stop: false };
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getSignature(page, selector) {
  try {
    return await page.evaluate((sel) => {
      const el = document.querySelector(sel) || document.body;
      return el ? el.innerText : '';
    }, selector);
  } catch (err) {
    // Page pas encore prête / navigation en cours : on renvoie une valeur
    // neutre plutôt que de faire planter l'orchestrateur.
    return '';
  }
}

/**
 * Attend que la boucle du site courant se termine (ou que le délai
 * maximum de sécurité soit atteint), en échantillonnant le contenu visible.
 */
async function waitForLoopToComplete(page, siteConfig, controlFile) {
  const {
    signatureSelector,
    minLoopMs,
    maxLoopMs,
    sampleIntervalMs,
    stableRepeatsToConfirm,
  } = siteConfig;

  const start = Date.now();
  let baselineHash = null;
  let consecutiveMatches = 0;

  while (true) {
    const elapsed = Date.now() - start;

    const control = readControl(controlFile);
    if (control.stop) return 'stopped';

    if (elapsed >= maxLoopMs) {
      console.log(`[${siteConfig.name}] Délai max atteint (${maxLoopMs}ms), passage forcé au site suivant.`);
      return 'timeout';
    }

    const text = await getSignature(page, signatureSelector);
    const currentHash = hashText(text);

    if (elapsed >= minLoopMs) {
      if (baselineHash === null) {
        // On fige la référence une fois la durée minimale passée, pour
        // laisser le temps au contenu de se stabiliser après le chargement.
        baselineHash = currentHash;
        console.log(`[${siteConfig.name}] Référence de boucle fixée à ${Math.round(elapsed / 1000)}s.`);
      } else if (currentHash === baselineHash && currentHash !== hashText('')) {
        consecutiveMatches += 1;
        if (consecutiveMatches >= stableRepeatsToConfirm) {
          console.log(`[${siteConfig.name}] Boucle détectée comme terminée après ${Math.round(elapsed / 1000)}s.`);
          return 'loop-detected';
        }
      } else {
        consecutiveMatches = 0;
      }
    }

    await sleep(sampleIntervalMs);
  }
}

async function main() {
  const config = loadConfig();
  const controlFile = config.controlFile;

  if (!fs.existsSync(controlFile)) {
    fs.writeFileSync(controlFile, JSON.stringify({ stop: false }));
  }

  // Se connecte au Chromium déjà lancé en mode kiosk par start_stream.sh
  // (affichage sur le display Xvfb capturé par ffmpeg), via le port de
  // debug distant, plutôt que d'ouvrir une nouvelle fenêtre invisible.
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9222');
  const context = browser.contexts()[0];
  // Ne pas prendre pages()[0] à l'aveugle : si Chromium a ouvert un
  // écran interne (first-run, sign-in, chrome://...) dans une fenêtre à
  // part, ce serait celle-là plutôt que la vraie fenêtre kiosk. On filtre
  // les URLs internes/vides et on retombe sur pages()[0] seulement si
  // rien d'autre ne correspond.
  const realPage = context.pages().find((p) => {
    const url = p.url();
    return url && !url.startsWith('chrome://') && !url.startsWith('chrome-extension://') && url !== 'about:blank';
  });
  const page = realPage || context.pages()[0] || (await context.newPage());

  // IMPORTANT : pas de page.setViewportSize() ici. Sur un navigateur
  // externe attaché via CDP (pas lancé par Playwright), setViewportSize
  // n'agrandit PAS la vraie fenêtre : il ne fait qu'émuler des métriques
  // de rendu (Emulation.setDeviceMetricsOverride) pour la page. Si la
  // fenêtre réelle (--window-size au lancement de Chromium) ne fait pas
  // EXACTEMENT la même taille, Chrome centre le contenu émulé dans la
  // fenêtre réelle et laisse du vide autour — exactement le symptôme
  // "widget centré avec bandes noires" observé. La taille de fenêtre
  // réelle est déjà fixée au lancement de Chromium (stream_session.sh,
  // --window-size), donc on s'y fie plutôt que de la re-émuler ici.
  const cdp = await context.newCDPSession(page);
  try {
    const { windowId } = await cdp.send('Browser.getWindowForTarget');
    const { bounds } = await cdp.send('Browser.getWindowBounds', { windowId });
    console.log('Diagnostic — taille réelle de la fenêtre Chromium (CDP) :', JSON.stringify(bounds));
  } catch (err) {
    console.log('Diagnostic fenêtre CDP indisponible :', err.message);
  }

  let index = 0;
  console.log('Orchestrateur démarré.');

  while (true) {
    const control = readControl(controlFile);
    if (control.stop) {
      console.log('Signal d\'arrêt reçu, fin de l\'orchestrateur.');
      break;
    }

    const site = config.sites[index % config.sites.length];
    console.log(`Chargement de ${site.name} (${site.url})`);
    try {
      await page.goto(site.url, { waitUntil: 'networkidle', timeout: 30000 });
      // Simule un geste utilisateur réel (reconnu par Chrome comme "trusted")
      // pour débloquer l'audio/AudioContext bloqué par la politique autoplay.
      await page.mouse.click(50, 50).catch(() => {});
      const pageMetrics = await page.evaluate(() => {
        const rect = document.body.getBoundingClientRect();
        return {
          innerWidth: window.innerWidth,
          innerHeight: window.innerHeight,
          bodyRect: { top: rect.top, left: rect.left, width: rect.width, height: rect.height },
        };
      }).catch((err) => ({ error: err.message }));
      console.log(`[${site.name}] Diagnostic — dimensions vues par la page :`, JSON.stringify(pageMetrics));
    } catch (err) {
      console.log(`[${site.name}] Erreur de chargement (${err.message}), nouvelle tentative dans 10s.`);
      await sleep(10000);
      continue;
    }

    const result = await waitForLoopToComplete(page, site, controlFile);
    if (result === 'stopped') break;

    index += 1;
  }

  console.log('Orchestrateur arrêté proprement.');
  process.exit(0);
}

process.on('SIGTERM', () => {
  console.log('SIGTERM reçu.');
  const config = loadConfig();
  fs.writeFileSync(config.controlFile, JSON.stringify({ stop: true }));
});

main().catch((err) => {
  console.error('Erreur fatale orchestrateur:', err);
  process.exit(1);
});
