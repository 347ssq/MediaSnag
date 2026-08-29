document.addEventListener("DOMContentLoaded", () => {
    const urlInput = document.getElementById("urlInput");
    const analyzeBtn = document.getElementById("analyzeBtn");
    const downloadBtn = document.getElementById("downloadBtn");
    const videoInfoSection = document.getElementById("videoInfo");
    const qualitySection = document.getElementById("qualitySection");
    const progressSection = document.getElementById("progressSection");
    const qualityList = document.getElementById("qualityList");
    const audioOptions = document.getElementById("audioOptions");
    const historyList = document.getElementById("historyList");

    const thumbnail = document.getElementById("thumbnail");
    const videoTitle = document.getElementById("videoTitle");
    const videoDuration = document.getElementById("videoDuration");

    const progressFilename = document.getElementById("progressFilename");
    const progressPercent = document.getElementById("progressPercent");
    const progressFill = document.getElementById("progressFill");
    const progressSpeed = document.getElementById("progressSpeed");
    const progressEta = document.getElementById("progressEta");
    const progressStatus = document.getElementById("progressStatus");

    let currentUrl = "";
    let currentDlType = "video";
    let selectedQuality = "1080p";
    let history = JSON.parse(localStorage.getItem("downloadHistory") || "[]");

    renderHistory();

    document.querySelectorAll(".toggle-option").forEach(option => {
        option.addEventListener("click", () => {
            document.querySelectorAll(".toggle-option").forEach(o => o.classList.remove("active"));
            option.classList.add("active");
            currentDlType = option.dataset.type;

            if (currentUrl) {
                analyzeUrl(currentUrl);
            }
        });
    });

    analyzeBtn.addEventListener("click", () => {
        const url = urlInput.value.trim();
        if (!url) return;
        currentUrl = url;
        analyzeUrl(url);
    });

    urlInput.addEventListener("keypress", (e) => {
        if (e.key === "Enter") {
            analyzeBtn.click();
        }
    });

    async function analyzeUrl(url) {
        analyzeBtn.disabled = true;
        analyzeBtn.textContent = "分析中...";

        try {
            const infoResp = await fetch(`/api/info?url=${encodeURIComponent(url)}`);
            const info = await infoResp.json();

            if (info.title) {
                videoTitle.textContent = info.title;
                if (info.duration) {
                    const mins = Math.floor(info.duration / 60);
                    const secs = Math.floor(info.duration % 60);
                    videoDuration.textContent = `${mins}:${secs.toString().padStart(2, "0")}`;
                } else {
                    videoDuration.textContent = "";
                }
                if (info.thumbnail) {
                    thumbnail.src = info.thumbnail;
                }
                videoInfoSection.classList.remove("hidden");
            }

            const formatsResp = await fetch(`/api/formats?url=${encodeURIComponent(url)}`);
            const formats = await formatsResp.json();

            if (currentDlType === "video") {
                qualityList.replaceChildren();
                formats.qualities.forEach((q, i) => {
                    const div = document.createElement("div");
                    div.className = "quality-option" + (i === 0 ? " selected" : "");
                    div.textContent = q;
                    div.dataset.quality = q;
                    if (i === 0) selectedQuality = q;

                    div.addEventListener("click", () => {
                        document.querySelectorAll(".quality-option").forEach(o => o.classList.remove("selected"));
                        div.classList.add("selected");
                        selectedQuality = q;
                    });

                    qualityList.appendChild(div);
                });
                audioOptions.classList.add("hidden");
            } else {
                qualityList.replaceChildren();
                audioOptions.classList.remove("hidden");
            }

            qualitySection.classList.remove("hidden");
        } catch (err) {
            alert("分析失败: " + err.message);
        } finally {
            analyzeBtn.disabled = false;
            analyzeBtn.textContent = "分析";
        }
    }

    downloadBtn.addEventListener("click", async () => {
        const audioFormat = document.querySelector('input[name="audioFormat"]:checked')?.value;

        const body = {
            url: currentUrl,
            type: currentDlType,
            quality: selectedQuality,
        };
        if (currentDlType === "audio") {
            body.audio_format = audioFormat || "mp3_best";
        }

        downloadBtn.disabled = true;
        downloadBtn.textContent = "启动中...";
        progressSection.classList.remove("hidden");
        progressStatus.textContent = "";
        progressStatus.className = "progress-status";
        progressFill.style.width = "0%";

        try {
            const resp = await fetch("/api/download", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(body),
            });
            const data = await resp.json();

            if (data.task_id) {
                trackProgress(data.task_id);
            } else {
                throw new Error(data.error || "Unknown error");
            }
        } catch (err) {
            progressStatus.textContent = "启动失败: " + err.message;
            progressStatus.className = "progress-status error";
            downloadBtn.disabled = false;
            downloadBtn.textContent = "开始下载";
        }
    });

    function trackProgress(taskId) {
        const evtSource = new EventSource(`/api/progress?id=${taskId}`);

        evtSource.onmessage = (event) => {
            const data = JSON.parse(event.data);

            progressFilename.textContent = data.filename || "准备中...";
            progressPercent.textContent = `${Math.round(data.progress)}%`;
            progressFill.style.width = `${data.progress}%`;

            if (data.speed) {
                const speedMB = (data.speed / 1024 / 1024).toFixed(2);
                progressSpeed.textContent = `速度: ${speedMB} MB/s`;
            } else {
                progressSpeed.textContent = "速度: --";
            }

            if (data.eta) {
                const etaMin = Math.floor(data.eta / 60);
                const etaSec = data.eta % 60;
                progressEta.textContent = `剩余: ${etaMin}:${etaSec.toString().padStart(2, "0")}`;
            } else {
                progressEta.textContent = "剩余: --";
            }

            if (data.status === "completed") {
                evtSource.close();
                progressStatus.textContent = "下载完成!";
                progressStatus.className = "progress-status success";
                downloadBtn.disabled = false;
                downloadBtn.textContent = "开始下载";
                addToHistory(currentUrl, selectedQuality, "completed");
            } else if (data.status === "error") {
                evtSource.close();
                progressStatus.textContent = "下载失败: " + (data.error || "Unknown error");
                progressStatus.className = "progress-status error";
                downloadBtn.disabled = false;
                downloadBtn.textContent = "开始下载";
                addToHistory(currentUrl, selectedQuality, "error");
            } else if (data.status === "processing") {
                progressStatus.textContent = "正在合并/转码...";
                progressStatus.className = "progress-status";
            }
        };

        evtSource.onerror = () => {
            evtSource.close();
            progressStatus.textContent = "连接中断";
            progressStatus.className = "progress-status error";
            downloadBtn.disabled = false;
            downloadBtn.textContent = "开始下载";
        };
    }

    function addToHistory(url, quality, status) {
        const item = {
            url,
            quality,
            status,
            time: new Date().toISOString(),
        };
        history.unshift(item);
        if (history.length > 20) history = history.slice(0, 20);
        localStorage.setItem("downloadHistory", JSON.stringify(history));
        renderHistory();
    }

    function renderHistory() {
        historyList.replaceChildren();
        if (history.length === 0) {
            const p = document.createElement("p");
            p.className = "empty";
            p.textContent = "暂无下载记录";
            historyList.appendChild(p);
            return;
        }

        history.forEach(item => {
            const div = document.createElement("div");
            div.className = "history-item";

            const icon = document.createElement("div");
            icon.className = `status-icon ${item.status}`;
            icon.textContent = item.status === "completed" ? "✓" : item.status === "error" ? "✗" : "↓";

            const info = document.createElement("div");
            info.className = "info";

            const name = document.createElement("div");
            name.className = "name";
            name.textContent = item.url;

            const meta = document.createElement("div");
            meta.className = "meta";
            const time = new Date(item.time);
            meta.textContent = `${item.quality} · ${time.toLocaleString("zh-CN")}`;

            info.appendChild(name);
            info.appendChild(meta);
            div.appendChild(icon);
            div.appendChild(info);
            historyList.appendChild(div);
        });
    }
});
