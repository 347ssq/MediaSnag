// ==UserScript==
// @name         通用视频/音频下载器
// @namespace    http://tampermonkey.net/
// @version      3.9
// @description  在视频页面显示下载按钮，支持视频、音频和音效素材下载；其它网站提供通用媒体扫描、页面对照、预览和下载
// @author       Qoder
// @match        *://*/*
// @grant        GM_setClipboard
// @grant        GM_addStyle
// @grant        GM_notification
// @run-at       document-idle
// @license      MIT
// ==/UserScript==

(function() {
    'use strict';

    const isSoundDino = location.hostname.includes('sounddino.com');

    function isVideoSite() {
        const host = location.hostname;
        const videoSites = [
            'youtube.com', 'youtu.be',
            'twitter.com', 'x.com',
            'instagram.com',
            'tiktok.com', 'douyin.com',
            'vimeo.com',
            'facebook.com', 'fb.watch',
            'bilibili.com',
            'twitch.tv',
            'dailymotion.com',
            'reddit.com',
            'weibo.com'
        ];
        return videoSites.some(site => host.includes(site));
    }

    const isGenericSite = !isVideoSite() && !isSoundDino;
    if (isGenericSite && window.self !== window.top) return;

    GM_addStyle(`
        .media-dl-btn {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            padding: 0 12px;
            height: 32px;
            border: none;
            border-radius: 18px;
            font-size: 13px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.2s;
            margin-left: 4px;
            white-space: nowrap;
        }
        .media-dl-btn:hover {
            opacity: 0.85;
            transform: scale(1.03);
        }
        .media-dl-btn.video {
            background: #cc0000;
            color: #fff;
        }
        .media-dl-btn.audio {
            background: #1db954;
            color: #fff;
        }
        .media-dl-btn svg {
            width: 15px;
            height: 15px;
            fill: currentColor;
            flex-shrink: 0;
        }
        .media-dl-toast {
            position: fixed;
            bottom: 80px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(0,0,0,0.85);
            color: #fff;
            padding: 12px 24px;
            border-radius: 8px;
            font-size: 14px;
            z-index: 99999;
            opacity: 0;
            transition: opacity 0.3s;
            pointer-events: none;
        }
        .media-dl-toast.show {
            opacity: 1;
        }
        .media-dl-fallback {
            position: fixed;
            bottom: 20px;
            right: 20px;
            z-index: 99998;
            display: flex;
            gap: 6px;
        }
        .media-dl-fallback .media-dl-btn {
            margin-left: 0;
            box-shadow: 0 2px 10px rgba(0,0,0,0.2);
        }
        .media-dl-btn.sdino-track {
            height: 26px;
            padding: 0 10px;
            font-size: 12px;
            margin-left: 10px;
            background: #1db954;
            color: #fff;
        }
        .media-dl-panel {
            position: fixed;
            bottom: 70px;
            right: 20px;
            z-index: 99999;
            width: 340px;
            max-height: 60vh;
            overflow-y: auto;
            background: #fff;
            color: #222;
            border-radius: 12px;
            box-shadow: 0 4px 24px rgba(0,0,0,0.25);
            padding: 12px;
            font-size: 13px;
            line-height: 1.4;
        }
        .media-dl-panel-head {
            display: flex;
            justify-content: space-between;
            align-items: center;
            font-weight: 600;
            margin-bottom: 8px;
        }
        .media-dl-panel-close {
            border: none;
            background: none;
            font-size: 16px;
            cursor: pointer;
            color: #888;
            padding: 0 4px;
        }
        .media-dl-panel-item {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 8px;
            border-radius: 8px;
            cursor: pointer;
        }
        .media-dl-panel-item:hover {
            background: #f2f2f2;
        }
        .media-dl-panel-item.dim {
            opacity: 0.55;
        }
        .media-dl-panel-tag {
            flex-shrink: 0;
            font-size: 11px;
            color: #fff;
            border-radius: 4px;
            padding: 2px 6px;
        }
        .media-dl-panel-tag.video { background: #cc0000; }
        .media-dl-panel-tag.audio { background: #1db954; }
        .media-dl-panel-tag.page { background: #666; }
        .media-dl-panel-labels {
            flex: 1;
            min-width: 0;
            display: flex;
            flex-direction: column;
            gap: 1px;
        }
        .media-dl-panel-name {
            font-size: 13px;
            font-weight: 500;
            color: #222;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .media-dl-panel-sub {
            font-size: 11px;
            color: #999;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .media-dl-panel-playing {
            flex-shrink: 0;
            font-size: 10px;
            color: #1db954;
            border: 1px solid #1db954;
            border-radius: 8px;
            padding: 1px 6px;
            white-space: nowrap;
        }
        .media-dl-panel-empty {
            color: #888;
            padding: 8px;
        }
        .media-dl-panel-filter {
            width: 100%;
            box-sizing: border-box;
            margin-bottom: 8px;
            padding: 7px 10px;
            border: 1px solid #e3e3e3;
            border-radius: 8px;
            font-size: 12px;
            outline: none;
            background: #fafafa;
            color: #222;
        }
        .media-dl-panel-filter:focus {
            border-color: #1db954;
            background: #fff;
        }
        .media-dl-panel-count {
            font-weight: 400;
            font-size: 11px;
            color: #999;
            margin-left: 6px;
        }
        .media-dl-hl {
            outline: 2px solid #1db954 !important;
            outline-offset: 2px;
            box-shadow: 0 0 0 4px rgba(29,185,84,0.25) !important;
        }
        .media-dl-panel-preview {
            flex-shrink: 0;
            border: 1px solid #1db954;
            background: #fff;
            color: #1db954;
            border-radius: 12px;
            padding: 2px 8px;
            font-size: 11px;
            cursor: pointer;
        }
        .media-dl-panel-preview:hover {
            background: #1db954;
            color: #fff;
        }
        .media-dl-preview {
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            z-index: 100000;
            width: min(480px, 90vw);
            background: #fff;
            color: #222;
            border-radius: 12px;
            box-shadow: 0 8px 40px rgba(0,0,0,0.35);
            padding: 12px;
            font-size: 13px;
        }
        .media-dl-preview-head {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 8px;
            margin-bottom: 8px;
            font-weight: 600;
        }
        .media-dl-preview-title {
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .media-dl-preview video {
            width: 100%;
            max-height: 320px;
            background: #000;
            border-radius: 8px;
        }
        .media-dl-preview audio {
            width: 100%;
        }
        .media-dl-preview-foot {
            display: flex;
            justify-content: flex-end;
            margin-top: 10px;
        }
        .media-dl-preview-backdrop {
            position: fixed;
            inset: 0;
            z-index: 99999;
            background: rgba(0,0,0,0.45);
        }
    `);

    function showToast(msg) {
        let toast = document.querySelector('.media-dl-toast');
        if (!toast) {
            toast = document.createElement('div');
            toast.className = 'media-dl-toast';
            document.body.appendChild(toast);
        }
        toast.textContent = msg;
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), 3000);
    }

    function createButton(type) {
        const url = window.location.href;
        const scheme = type === 'video' ? 'ytdl' : 'ytdla';
        const btn = document.createElement('a');
        btn.href = `${scheme}://${encodeURIComponent(url)}`;
        btn.className = `media-dl-btn ${type}`;
        btn.style.textDecoration = 'none';
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 24 24');
        const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
        if (type === 'video') {
            path.setAttribute('d', 'M5 20h14v-2H5v2zM19 9h-4V3H9v6H5l7 7 7-7z');
        } else {
            path.setAttribute('d', 'M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z');
        }
        svg.appendChild(path);
        const span = document.createElement('span');
        span.textContent = type === 'video' ? '下载视频' : '下载音频';
        btn.appendChild(svg);
        btn.appendChild(span);
        btn.addEventListener('click', function() {
            showToast(`正在打开${type === 'video' ? '视频' : '音频'}下载器...`);
        });
        return btn;
    }

    function createButtonPair() {
        const wrap = document.createElement('span');
        wrap.style.cssText = 'display:inline-flex;align-items:center;margin-left:8px;';
        wrap.appendChild(createButton('video'));
        wrap.appendChild(createButton('audio'));
        return wrap;
    }

    function sameRowAs(a, b) {
        const ra = a.getBoundingClientRect();
        const rb = b.getBoundingClientRect();
        return Math.abs(ra.top - rb.top) < 15;
    }

    // ========== YouTube ==========
    function insertYouTube() {
        document.querySelectorAll('.media-dl-yt').forEach(el => el.remove());

        // Anchor on the VISIBLE like/dislike button — most reliable anchor
        const likeBtns = document.querySelectorAll('segmented-like-dislike-button-view-model');
        let likeBtn = null;
        for (const b of likeBtns) {
            if (b.offsetWidth > 0) { likeBtn = b; break; }
        }
        if (!likeBtn) return false;

        const tlbc = likeBtn.closest('#top-level-buttons-computed');
        const mr = likeBtn.closest('ytd-menu-renderer');
        if (!tlbc) return false;

        const wrap = createButtonPair();
        wrap.className = 'media-dl-yt';

        // Attempt 1: append into the like button's row container
        tlbc.appendChild(wrap);
        if (sameRowAs(wrap, likeBtn)) return true;

        // Attempt 2: as direct child of ytd-menu-renderer
        wrap.remove();
        if (mr) {
            const flexible = mr.querySelector('#flexible-item-buttons');
            if (flexible) {
                flexible.insertAdjacentElement('afterend', wrap);
            } else {
                mr.appendChild(wrap);
            }
            if (sameRowAs(wrap, likeBtn)) return true;
        }

        // Attempt 3: absolutely position at right edge of action bar
        wrap.remove();
        const anchor = mr || tlbc;
        anchor.style.position = 'relative';
        wrap.style.position = 'absolute';
        wrap.style.right = '0';
        wrap.style.top = '0';
        wrap.style.margin = '0';
        anchor.appendChild(wrap);
        return true;
    }

    // ========== Bilibili ==========
    function insertBilibili() {
        document.querySelectorAll('.media-dl-bili').forEach(el => el.remove());

        const toolbar = document.querySelector('.video-toolbar-left-main')
            || document.querySelector('.video-toolbar-left')
            || document.querySelector('.toolbar-left')
            || document.querySelector('.video-info-operate');

        if (!toolbar) return false;

        const items = toolbar.querySelectorAll('.toolbar-left-item-wrap');
        const lastItem = items.length > 0 ? items[items.length - 1] : null;

        const wrap = createButtonPair();
        wrap.className = 'toolbar-left-item-wrap media-dl-bili';

        if (lastItem) {
            lastItem.insertAdjacentElement('afterend', wrap);
        } else {
            toolbar.appendChild(wrap);
        }
        return true;
    }

    // ========== Direct file download (for sound-effect sites) ==========
    function directDownload(url, filename) {
        const a = document.createElement('a');
        a.href = url;
        if (filename) a.download = filename;
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        setTimeout(() => { if (a.parentElement) a.parentElement.removeChild(a); }, 1000);
    }

    // ========== SoundDino (sound effects) ==========
    function insertSoundDino() {
        const tracks = document.querySelectorAll('li.playtrack[data-track]');
        if (tracks.length === 0) return false;

        tracks.forEach(track => {
            if (track.hasAttribute('data-dl-added')) return;
            track.setAttribute('data-dl-added', '1');
            const btn = document.createElement('button');
            btn.className = 'media-dl-btn sdino-track';
            btn.textContent = '下载';
            btn.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                const path = track.getAttribute('data-track');
                const url = path.startsWith('http') ? path : location.origin + path;
                directDownload(url, path.split('/').pop());
                showToast('开始下载音效...');
            });
            track.appendChild(btn);
        });

        return true;
    }

    // ========== Generic mode (unadapted sites) ==========
    function sendToApp(url) {
        const a = document.createElement('a');
        a.href = `ytdl://${encodeURIComponent(url)}`;
        a.style.display = 'none';
        document.body.appendChild(a);
        a.click();
        setTimeout(() => { if (a.parentElement) a.remove(); }, 500);
    }

    function cleanText(t) {
        return (t || '').replace(/\s+/g, ' ').trim();
    }
    function validLabel(t) {
        return t.length >= 2 && t.length <= 60;
    }
    // 兜底：从一个容器里挑最像"标题"的可见文本（跳过时间戳/纯数字/按钮常见词）
    const actionWords = ['查看更多', '查看全部', '更多', '下载', '下載', '播放', '暂停', '暫停',
        '预览', '預覽', '收藏', '分享', '登录', '登錄', '登入', '注册', '註冊', '立即购买',
        'download', 'play', 'pause', 'preview', 'more', 'share', 'save', 'login'];
    function leafTexts(node) {
        const leaves = [];
        (function walk(e) {
            if (!e) return;
            if (e.children && e.children.length > 0) {
                for (const c of e.children) walk(c);
            } else {
                const t = cleanText(e.textContent);
                if (t) leaves.push(t);
            }
        })(node);
        return leaves;
    }
    function cardTitleText(node) {
        for (const t of leafTexts(node)) {
            if (!validLabel(t)) continue;
            if (/^[\d:.\-/\s]+$/.test(t)) continue; // 00:15 / 1080 / 12.5 之类
            if (actionWords.includes(t.toLowerCase())) continue;
            return t;
        }
        return '';
    }

    // 从元素向上查找页面中可读的名称（标题/卡片文字），用于和界面对照
    function labelForElement(el) {
        if (!el || !el.closest) return '';
        // 第一遍：沿祖先链找强信号（属性 / 标题标签 / title 类 class / img alt）
        let node = el;
        for (let i = 0; i < 7 && node && node !== document.documentElement && node !== document.body; i++) {
            const direct = node.getAttribute && (
                node.getAttribute('title') ||
                node.getAttribute('aria-label') ||
                node.getAttribute('alt') ||
                node.getAttribute('data-title') ||
                node.getAttribute('data-name')
            );
            if (direct && validLabel(cleanText(direct))) return cleanText(direct);

            if (node.querySelectorAll) {
                const named = node.querySelectorAll(
                    'h1,h2,h3,h4,h5,h6,[class*="title"],[class*="name"],[class*="caption"],img[alt]'
                );
                for (const m of named) {
                    // 不借用兄弟卡片的标题
                    const holder = m.closest && m.closest('li');
                    if (holder && !holder.contains(el)) continue;
                    const t = cleanText(m.tagName === 'IMG' ? (m.getAttribute('alt') || '') : m.textContent);
                    if (validLabel(t)) return t;
                }
            }
            node = node.parentElement;
        }
        // 第二遍：列表项则取本卡片内的可读文本（跳过时间戳/按钮词）
        const li = el.closest('li');
        if (li) {
            const t = cardTitleText(li);
            if (t) return t;
        }
        // 第三遍：非列表媒体，向上找"只包含本媒体"的容器里的较长文本
        node = el;
        for (let i = 0; i < 6 && node && node !== document.body; i++) {
            if (i >= 2 && node.querySelectorAll && node.querySelectorAll('audio, video').length <= 1) {
                for (const t of leafTexts(node)) {
                    if (validLabel(t) && t.length >= 4 && !/^[\d:.\-/\s]+$/.test(t)
                        && !actionWords.includes(t.toLowerCase())) return t;
                }
            }
            node = node.parentElement;
        }
        // 第四遍：页面主标题兜底
        const h1 = document.querySelector('h1');
        if (h1 && validLabel(cleanText(h1.textContent))) return cleanText(h1.textContent);
        return '';
    }

    function isPlaying(el) {
        return !!el && typeof el.paused === 'boolean' && !el.paused && !el.ended && el.currentTime > 0;
    }

    function scanMedia() {
        const found = [];
        const seen = new Set();
        const push = (url, type, el) => {
            if (!url || url.startsWith('data:') || seen.has(url)) return;
            seen.add(url);
            found.push({ url, type, el: el || null, label: labelForElement(el), playing: isPlaying(el) });
        };
        document.querySelectorAll('video').forEach(v => {
            push(v.currentSrc || v.src, 'video', v);
            v.querySelectorAll('source').forEach(s => push(s.src, 'video', v));
        });
        document.querySelectorAll('audio').forEach(a => {
            push(a.currentSrc || a.src, 'audio', a);
            a.querySelectorAll('source').forEach(s => push(s.src, 'audio', a));
        });
        const videoExt = /\.(mp4|webm|mkv|mov|m4v|avi|flv|ts)(\?|#|$)/i;
        const audioExt = /\.(mp3|m4a|wav|ogg|oga|flac|aac|opus)(\?|#|$)/i;
        document.querySelectorAll('a[href]').forEach(a => {
            const h = a.href;
            if (videoExt.test(h)) push(h, 'video', a);
            else if (audioExt.test(h)) push(h, 'audio', a);
        });
        document.querySelectorAll('meta[property="og:video"], meta[property="og:video:url"], meta[property="og:video:secure_url"]').forEach(m => push(m.content, 'video', null));
        document.querySelectorAll('meta[property="og:audio"], meta[property="og:audio:url"]').forEach(m => push(m.content, 'audio', null));
        found.sort((a, b) => (b.playing ? 1 : 0) - (a.playing ? 1 : 0));
        return found;
    }

    let highlightedEl = null;
    function isVisibleEl(e) {
        const r = e.getBoundingClientRect();
        return r.width > 0 && r.height > 0;
    }
    function highlightSource(el) {
        unhighlightSource();
        if (!el || !el.isConnected) return;
        let target = null;
        if (isVisibleEl(el)) {
            target = el; // 媒体本身可见（如正常视频），直接高亮
        } else {
            const li = el.closest('li');
            if (li && isVisibleEl(li)) {
                target = li; // 隐藏媒体在可见列表卡片内，高亮整张卡片
            } else if (!li) {
                // 无卡片归属：向上找最近一个"大小适中"的可见祖先
                // （跳过细条/零碎元素，也跳过整页大容器）
                let t = el.parentElement;
                let hops = 0;
                while (t && t !== document.body && t !== document.documentElement && hops < 8) {
                    if (isVisibleEl(t)) {
                        const r = t.getBoundingClientRect();
                        const area = r.width * r.height;
                        if (area >= 6000 && area <= 200000) { target = t; break; }
                    }
                    t = t.parentElement;
                    hops++;
                }
            }
        }
        if (!target) return;
        highlightedEl = target;
        target.classList.add('media-dl-hl');
        try { target.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); } catch (e) {}
    }
    function unhighlightSource() {
        if (highlightedEl) {
            highlightedEl.classList.remove('media-dl-hl');
            highlightedEl = null;
        }
    }

    function fileNameFromUrl(url) {
        try {
            const clean = url.split(/[?#]/)[0];
            const name = decodeURIComponent(clean.split('/').pop());
            return name || 'media';
        } catch (e) {
            return 'media';
        }
    }

    async function fetchAndSave(url, filename) {
        try {
            const res = await fetch(url, { credentials: 'include' });
            if (!res.ok) return false;
            const blob = await res.blob();
            const obj = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = obj;
            a.download = filename;
            a.style.display = 'none';
            document.body.appendChild(a);
            a.click();
            setTimeout(() => { a.remove(); URL.revokeObjectURL(obj); }, 2000);
            return true;
        } catch (e) {
            return false;
        }
    }

    function closeGenericPanel() {
        unhighlightSource();
        const p = document.querySelector('.media-dl-panel');
        if (p) p.remove();
    }

    async function handleGenericItem(item) {
        closeGenericPanel();
        const url = item.url;
        if (url.startsWith('blob:') || url.startsWith('mediasource:') || /\.m3u8|m3u8(\?|$)|\.mpd(\?|$)/i.test(url)) {
            showToast('流媒体无法直接下载，已转交MediaSnag处理本页...');
            sendToApp(location.href);
            return;
        }
        const filename = fileNameFromUrl(url);
        const ext = filename.includes('.') ? filename.split('.').pop() : (item.type === 'audio' ? 'mp3' : 'mp4');
        const saveName = item.label ? `${item.label.replace(/[\\/:*?"<>|]/g, '_')}.${ext}` : filename;
        showToast(`正在下载 ${item.label || filename} ...`);
        const ok = await fetchAndSave(url, saveName);
        if (!ok) {
            showToast('直接下载失败，已转交MediaSnag...');
            sendToApp(url);
        }
    }

    function closePreview() {
        const pv = document.querySelector('.media-dl-preview');
        if (pv) {
            pv.querySelectorAll('video, audio').forEach(m => { try { m.pause(); } catch (e) {} });
            pv.remove();
        }
        const bd = document.querySelector('.media-dl-preview-backdrop');
        if (bd) bd.remove();
    }

    function openPreview(item) {
        closePreview();
        const filename = fileNameFromUrl(item.url);

        const backdrop = document.createElement('div');
        backdrop.className = 'media-dl-preview-backdrop';
        backdrop.addEventListener('click', closePreview);
        document.body.appendChild(backdrop);

        const box = document.createElement('div');
        box.className = 'media-dl-preview';

        const head = document.createElement('div');
        head.className = 'media-dl-preview-head';
        const title = document.createElement('span');
        title.className = 'media-dl-preview-title';
        title.textContent = item.label || filename;
        const closeBtn = document.createElement('button');
        closeBtn.className = 'media-dl-panel-close';
        closeBtn.textContent = '✕';
        closeBtn.addEventListener('click', closePreview);
        head.appendChild(title);
        head.appendChild(closeBtn);
        box.appendChild(head);

        const isStream = item.url.startsWith('blob:') || item.url.startsWith('mediasource:');
        const player = document.createElement(item.type === 'audio' && !isStream ? 'audio' : 'video');
        player.controls = true;
        player.src = item.url;
        player.preload = 'metadata';
        player.addEventListener('error', () => {
            showToast('预览加载失败（可能是跨域或防盗链限制）');
        });
        box.appendChild(player);

        const foot = document.createElement('div');
        foot.className = 'media-dl-preview-foot';
        const dlBtn = document.createElement('button');
        dlBtn.className = 'media-dl-btn ' + item.type;
        dlBtn.textContent = item.type === 'video' ? '下载视频' : '下载音频';
        dlBtn.addEventListener('click', () => {
            closePreview();
            handleGenericItem(item);
        });
        foot.appendChild(dlBtn);
        box.appendChild(foot);

        document.body.appendChild(box);
    }

    function openGenericPanel() {
        closeGenericPanel();
        const panel = document.createElement('div');
        panel.className = 'media-dl-panel';

        const items = scanMedia();

        const head = document.createElement('div');
        head.className = 'media-dl-panel-head';
        const title = document.createElement('span');
        title.textContent = '页面中发现的媒体';
        if (items.length > 0) {
            const count = document.createElement('span');
            count.className = 'media-dl-panel-count';
            count.textContent = `${items.length} 项`;
            title.appendChild(count);
        }
        const closeBtn = document.createElement('button');
        closeBtn.className = 'media-dl-panel-close';
        closeBtn.textContent = '✕';
        closeBtn.addEventListener('click', closeGenericPanel);
        head.appendChild(title);
        head.appendChild(closeBtn);
        panel.appendChild(head);

        const rowRefs = [];
        if (items.length === 0) {
            const empty = document.createElement('div');
            empty.className = 'media-dl-panel-empty';
            empty.textContent = '未找到直接媒体，可尝试把整页交给下载器';
            panel.appendChild(empty);
        } else if (items.length >= 4) {
            const filter = document.createElement('input');
            filter.className = 'media-dl-panel-filter';
            filter.placeholder = '筛选（名称或文件名）…';
            filter.addEventListener('input', () => {
                const q = filter.value.trim().toLowerCase();
                rowRefs.forEach(r => {
                    r.row.style.display = (!q || r.text.includes(q)) ? '' : 'none';
                });
            });
            panel.appendChild(filter);
        }

        items.forEach(item => {
            const filename = fileNameFromUrl(item.url);
            const row = document.createElement('div');
            row.className = 'media-dl-panel-item';
            const tag = document.createElement('span');
            tag.className = `media-dl-panel-tag ${item.type}`;
            tag.textContent = item.type === 'video' ? '视频' : '音频';
            const labels = document.createElement('div');
            labels.className = 'media-dl-panel-labels';
            const name = document.createElement('span');
            name.className = 'media-dl-panel-name';
            name.textContent = item.label || filename;
            name.title = item.label || filename;
            labels.appendChild(name);
            if (item.label) {
                const sub = document.createElement('span');
                sub.className = 'media-dl-panel-sub';
                sub.textContent = filename;
                labels.appendChild(sub);
            }
            row.appendChild(tag);
            row.appendChild(labels);
            if (item.playing) {
                const playing = document.createElement('span');
                playing.className = 'media-dl-panel-playing';
                playing.textContent = '播放中';
                row.appendChild(playing);
            }
            const previewBtn = document.createElement('button');
            previewBtn.className = 'media-dl-panel-preview';
            previewBtn.textContent = '预览';
            previewBtn.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();
                openPreview(item);
            });
            row.appendChild(previewBtn);
            if (item.el) {
                row.addEventListener('mouseenter', () => highlightSource(item.el));
                row.addEventListener('mouseleave', unhighlightSource);
            } else {
                row.classList.add('dim');
            }
            row.addEventListener('click', () => handleGenericItem(item));
            panel.appendChild(row);
            rowRefs.push({ row, text: `${(item.label || '')} ${filename}`.toLowerCase() });
        });

        const pageRow = document.createElement('div');
        pageRow.className = 'media-dl-panel-item';
        const pageTag = document.createElement('span');
        pageTag.className = 'media-dl-panel-tag page';
        pageTag.textContent = '整页';
        const pageLabels = document.createElement('div');
        pageLabels.className = 'media-dl-panel-labels';
        const pageName = document.createElement('span');
        pageName.className = 'media-dl-panel-name';
        pageName.textContent = '把本页面交给MediaSnag尝试';
        pageLabels.appendChild(pageName);
        pageRow.appendChild(pageTag);
        pageRow.appendChild(pageLabels);
        pageRow.addEventListener('click', () => {
            closeGenericPanel();
            showToast('正在打开MediaSnag...');
            sendToApp(location.href);
        });
        panel.appendChild(pageRow);

        document.body.appendChild(panel);
    }

    function insertGeneric() {
        if (document.querySelector('.media-dl-generic')) return true;
        const container = document.createElement('div');
        container.className = 'media-dl-fallback media-dl-generic';
        const btn = document.createElement('button');
        btn.className = 'media-dl-btn video';
        btn.textContent = '下载媒体';
        btn.addEventListener('click', e => {
            e.preventDefault();
            e.stopPropagation();
            if (document.querySelector('.media-dl-panel')) closeGenericPanel();
            else openGenericPanel();
        });
        container.appendChild(btn);
        document.body.appendChild(container);
        return true;
    }

    // ========== Fallback ==========
    function insertFallback() {
        if (document.querySelector('.media-dl-fallback')) return;
        const container = document.createElement('div');
        container.className = 'media-dl-fallback';
        container.appendChild(createButton('video'));
        container.appendChild(createButton('audio'));
        document.body.appendChild(container);
    }

    // ========== Main logic ==========
    const host = location.hostname;
    const isYT = host.includes('youtube.com') || host.includes('youtu.be');
    const isBili = host.includes('bilibili.com');

    function tryInsert() {
        let ok;
        if (isYT) ok = insertYouTube();
        else if (isBili) ok = insertBilibili();
        else if (isSoundDino) ok = insertSoundDino();
        else if (isGenericSite) ok = insertGeneric();
        else { insertFallback(); ok = true; }
        // Site-specific anchor never appeared (layout change / slow page):
        // always give the user a visible universal button as a last resort.
        if (!ok && attempts >= 10) {
            insertFallback();
            ok = true;
        }
        return ok;
    }

    // Initial insertion with retries (page may still be rendering)
    let attempts = 0;
    function attemptInsert() {
        if (tryInsert()) return;
        attempts++;
        if (attempts <= 10) {
            setTimeout(attemptInsert, 500);
        }
    }
    attemptInsert();

    // SPA navigation handling
    if (isYT) {
        document.addEventListener('yt-navigate-finish', () => {
            setTimeout(insertYouTube, 300);
            setTimeout(insertYouTube, 1000);
            setTimeout(insertYouTube, 2000);
        });
    }

    if (isBili) {
        window.addEventListener('popstate', () => {
            setTimeout(insertBilibili, 800);
            setTimeout(insertBilibili, 2000);
        });
    }

    // Persistent check: re-insert if buttons get removed by SPA re-render
    setInterval(() => {
        if (isSoundDino) {
            if (document.querySelector('li.playtrack[data-track]:not([data-dl-added])')) insertSoundDino();
            return;
        }
        const siteSelector = isYT ? '.media-dl-yt'
            : (isBili ? '.media-dl-bili'
            : (isGenericSite ? '.media-dl-generic' : '.media-dl-fallback'));
        const hasSiteBtn = !!document.querySelector(siteSelector);
        const hasFallback = !!document.querySelector('.media-dl-fallback');
        if (!hasSiteBtn && !hasFallback) {
            tryInsert();
        } else if (hasSiteBtn && hasFallback && !isGenericSite) {
            // Site-specific button took over: drop the temporary fallback
            document.querySelectorAll('.media-dl-fallback:not(.media-dl-generic)')
                .forEach(el => el.remove());
        }
    }, 2000);

})();
