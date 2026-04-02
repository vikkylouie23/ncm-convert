import "./styles.css";

const fileInput = document.querySelector("#file-input");
const pickFilesButton = document.querySelector("#pick-files-button");
const downloadAllButton = document.querySelector("#download-all-button");
const zipButton = document.querySelector("#zip-button");
const clearButton = document.querySelector("#clear-button");
const resultsContainer = document.querySelector("#results");
const statusText = document.querySelector("#status-text");
const progressText = document.querySelector("#progress-text");
const summaryText = document.querySelector("#summary-text");
const resultsCount = document.querySelector("#results-count");

const appState = {
  total: 0,
  processed: 0,
  succeeded: 0,
  entries: [],
  processing: false,
};

let decryptLoadPromise = null;

async function ensureDecryptReady() {
  if (window.decrypt && typeof window.decrypt.Decrypt === "function") {
    return;
  }

  if (!decryptLoadPromise) {
    decryptLoadPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = new URL("./vendor/decrypt.js", window.location.href).toString();
      script.async = true;

      script.addEventListener("load", () => {
        if (window.decrypt && typeof window.decrypt.Decrypt === "function") {
          resolve();
          return;
        }

        reject(new Error("本地 decrypt.js 未正确加载。"));
      });

      script.addEventListener("error", () => {
        reject(new Error("解密引擎加载失败。"));
      });

      document.head.append(script);
    }).catch((error) => {
      decryptLoadPromise = null;
      throw error;
    });
  }

  await decryptLoadPromise;
}

function updateToolbarState() {
  const hasEntries = appState.entries.length > 0;
  const isBusy = appState.processing;
  pickFilesButton.disabled = isBusy;
  fileInput.disabled = isBusy;
  downloadAllButton.disabled = !hasEntries || isBusy;
  zipButton.disabled = !hasEntries || isBusy;
  clearButton.disabled = !hasEntries || isBusy;
  resultsCount.textContent = `${appState.entries.length} 个文件`;
}

function updateStatus(message) {
  statusText.textContent = message;
  progressText.textContent = `${appState.processed} / ${appState.total}`;
  if (appState.total === 0) {
    summaryText.textContent = "还没有转换结果";
    return;
  }

  const failed = appState.processed - appState.succeeded;
  const pending = appState.total - appState.processed;
  summaryText.textContent =
    failed > 0 || pending > 0
      ? `成功 ${appState.succeeded} 个，失败 ${failed} 个，剩余 ${pending} 个`
      : `已成功转换 ${appState.succeeded} 个文件`;
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function releaseEntry(entry) {
  if (entry.blobUrl) {
    URL.revokeObjectURL(entry.blobUrl);
  }
  if (entry.pictureUrl && entry.pictureUrl.startsWith("blob:")) {
    URL.revokeObjectURL(entry.pictureUrl);
  }
}

function removeEntry(id) {
  const index = appState.entries.findIndex((entry) => entry.id === id);
  if (index === -1) return;

  const [entry] = appState.entries.splice(index, 1);
  releaseEntry(entry);
  const node = document.querySelector(`[data-entry-id="${id}"]`);
  node?.remove();
  updateToolbarState();

  if (appState.entries.length === 0 && appState.total === 0) {
    updateStatus("等待选择文件");
  } else {
    summaryText.textContent = `当前保留 ${appState.entries.length} 个结果`;
  }
}

function clearEntries({ resetProgress } = { resetProgress: true }) {
  appState.entries.forEach(releaseEntry);
  appState.entries = [];
  resultsContainer.innerHTML = "";

  if (resetProgress) {
    appState.total = 0;
    appState.processed = 0;
    appState.succeeded = 0;
    updateStatus("等待选择文件");
  }

  updateToolbarState();
}

async function tryNativeSave(blob, fileName) {
  try {
    const response = await fetch(`/__save__?filename=${encodeURIComponent(fileName)}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/octet-stream",
      },
      body: blob,
    });

    if (response.status === 404) {
      return "unsupported";
    }

    const payload = await response
      .json()
      .catch(() => ({ status: response.ok ? "saved" : "error" }));

    if (payload.status === "saved") {
      return "saved";
    }

    if (payload.status === "cancelled") {
      return "cancelled";
    }

    throw new Error(payload.message || "保存失败。");
  } catch (error) {
    if (error instanceof TypeError) {
      return "unsupported";
    }

    throw error;
  }
}

function triggerBrowserDownload(blobUrl, fileName) {
  const anchor = document.createElement("a");
  anchor.href = blobUrl;
  anchor.download = fileName;
  anchor.click();
}

async function saveBlob(blob, fileName, blobUrl) {
  const nativeResult = await tryNativeSave(blob, fileName);
  if (nativeResult === "saved" || nativeResult === "cancelled") {
    return nativeResult;
  }

  triggerBrowserDownload(blobUrl, fileName);
  return "saved";
}

function reportActionError(actionLabel, error) {
  console.error(`${actionLabel} failed`, error);
  updateStatus(`${actionLabel}失败`);
  window.alert(
    error instanceof Error ? `${actionLabel}失败：${error.message}` : `${actionLabel}失败`,
  );
}

function renderEntry(result, sourceFile) {
  const entryId = crypto.randomUUID();
  const blobUrl = URL.createObjectURL(result.blob);
  const pictureUrl = result.picture || "";
  const fileName = `${result.rawFilename}.${result.ext}`;
  const title = result.title || result.rawFilename || sourceFile.name;
  const artist = result.artist || "未知艺术家";
  const album = result.album || "未知专辑";
  const escapedBlobUrl = escapeHtml(blobUrl);
  const escapedPictureUrl = escapeHtml(pictureUrl);
  const escapedFileName = escapeHtml(fileName);
  const escapedTitle = escapeHtml(title);
  const escapedArtist = escapeHtml(artist);
  const escapedAlbum = escapeHtml(album);
  const escapedExt = escapeHtml(String(result.ext).toUpperCase());

  const article = document.createElement("article");
  article.className = "result-card";
  article.dataset.entryId = entryId;

  article.innerHTML = `
    <div class="cover-wrap">
      ${
        pictureUrl
          ? `<img class="cover" src="${escapedPictureUrl}" alt="${escapedTitle}" loading="lazy" />`
          : `<div class="cover cover-fallback">NO COVER</div>`
      }
    </div>
    <div class="result-main">
      <div class="meta-row">
        <div>
          <h3>${escapedTitle}</h3>
          <p>${escapedArtist}</p>
          <p class="album-line">${escapedAlbum}</p>
        </div>
        <span class="format-pill">${escapedExt}</span>
      </div>
      <audio controls preload="none" src="${escapedBlobUrl}"></audio>
      <div class="result-actions">
        <button class="inline-button" type="button" data-download-id="${entryId}">下载文件</button>
        <button class="inline-button inline-button-muted" type="button" data-remove-id="${entryId}">移除</button>
      </div>
      <p class="file-line">${escapedFileName}</p>
    </div>
  `;

  const entry = {
    id: entryId,
    fileName,
    blob: result.blob,
    blobUrl,
    pictureUrl,
  };

  article
    .querySelector(`[data-download-id="${entryId}"]`)
    ?.addEventListener("click", async () => {
      try {
        await saveBlob(entry.blob, entry.fileName, entry.blobUrl);
      } catch (error) {
        reportActionError("下载文件", error);
      }
    });

  article
    .querySelector(`[data-remove-id="${entryId}"]`)
    ?.addEventListener("click", () => removeEntry(entryId));

  resultsContainer.prepend(article);
  appState.entries.push(entry);

  updateToolbarState();
}

function renderError(file, error) {
  const escapedFileName = escapeHtml(file.name);
  const escapedMessage = escapeHtml(
    error instanceof Error ? error.message : String(error),
  );

  const article = document.createElement("article");
  article.className = "result-card result-card-error";
  article.innerHTML = `
    <div class="cover-wrap">
      <div class="cover cover-fallback">FAILED</div>
    </div>
    <div class="result-main">
      <div class="meta-row">
        <div>
          <h3>${escapedFileName}</h3>
          <p>转换失败</p>
        </div>
        <span class="format-pill format-pill-error">ERROR</span>
      </div>
      <p class="error-text">${escapedMessage}</p>
    </div>
  `;
  resultsContainer.prepend(article);
}

async function handleFiles(files) {
  if (appState.processing) return;

  appState.processing = true;
  updateToolbarState();
  clearEntries({ resetProgress: true });

  appState.total = files.length;
  appState.processed = 0;
  appState.succeeded = 0;
  updateStatus("正在加载解密引擎");

  try {
    await ensureDecryptReady();
    updateStatus("正在本地转换");

    for (const file of files) {
      try {
        const result = await window.decrypt.Decrypt(file);
        renderEntry(result, file);
        appState.succeeded += 1;
      } catch (error) {
        console.error("convert failed", file.name, error);
        renderError(file, error);
      } finally {
        appState.processed += 1;
        updateStatus("正在本地转换");
      }
    }

    if (appState.succeeded === appState.total) {
      updateStatus("全部转换完成");
    } else {
      updateStatus("转换完成，存在失败项");
    }
  } catch (error) {
    appState.processed = appState.total;
    updateStatus("解密引擎加载失败");
    renderError(
      { name: "decrypt.js" },
      error instanceof Error ? error : new Error(String(error)),
    );
  } finally {
    appState.processing = false;
    updateToolbarState();
  }
}

async function downloadZip() {
  if (!appState.entries.length) return;

  zipButton.disabled = true;
  zipButton.textContent = "正在生成 ZIP...";

  try {
    const { default: JSZip } = await import("jszip");
    const zip = new JSZip();
    for (const entry of appState.entries) {
      zip.file(entry.fileName, entry.blob, { compression: "STORE" });
    }

    const content = await zip.generateAsync({
      type: "blob",
      compression: "STORE",
      streamFiles: true,
    });
    const blobUrl = URL.createObjectURL(content);
    try {
      await saveBlob(content, "ncm-local-results.zip", blobUrl);
    } finally {
      setTimeout(() => URL.revokeObjectURL(blobUrl), 2000);
    }
  } catch (error) {
    reportActionError("生成 ZIP", error);
  } finally {
    zipButton.disabled = false;
    zipButton.textContent = "生成 ZIP";
  }
}

async function downloadAll() {
  downloadAllButton.disabled = true;
  downloadAllButton.textContent = "正在下载...";

  try {
    for (const entry of appState.entries) {
      const result = await saveBlob(entry.blob, entry.fileName, entry.blobUrl);
      if (result === "cancelled") {
        break;
      }
    }
  } catch (error) {
    reportActionError("下载全部", error);
  } finally {
    downloadAllButton.disabled = false;
    downloadAllButton.textContent = "下载全部";
  }
}

fileInput.addEventListener("change", async (event) => {
  const files = Array.from(event.target.files || []);
  event.target.value = "";
  if (!files.length) return;
  await handleFiles(files);
});

pickFilesButton.addEventListener("click", () => {
  if (appState.processing) return;
  fileInput.click();
});

downloadAllButton.addEventListener("click", downloadAll);
zipButton.addEventListener("click", downloadZip);
clearButton.addEventListener("click", () => {
  clearEntries({ resetProgress: true });
  fileInput.value = "";
});

updateToolbarState();
updateStatus("等待选择文件");
