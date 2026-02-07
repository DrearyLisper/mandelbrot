const TILE_SIZE = 256;
const MIN_ZOOM = 0;
const MAX_ZOOM = 45;
const SCROLL_THRESHOLD = 300; // accumulated deltaY needed to change one zoom level

const MapHook = {
  mounted() {
    this.cx = 0.5;
    this.cy = 0.5;
    this.zoom = 2;

    this.container = this.el;
    this.tileLayer = document.createElement("div");
    this.tileLayer.style.cssText = "position:absolute;top:0;left:0;width:100%;height:100%;";
    this.container.appendChild(this.tileLayer);

    this.tiles = new Map();
    this.dragging = false;
    this.lastX = 0;
    this.lastY = 0;
    this.pinchStartDist = null;
    this.pinchStartZoom = 0;
    this.scrollAccum = 0;
    this.dpr = Math.min(3, Math.max(1, Math.floor(window.devicePixelRatio || 1)));

    // Bind handlers for proper cleanup
    this._onMouseMove = this._handleMouseMove.bind(this);
    this._onMouseUp = this._handleMouseUp.bind(this);
    this._onTouchMove = this._handleTouchMove.bind(this);
    this._onTouchEnd = this._handleTouchEnd.bind(this);

    this.statusEl = document.getElementById("map-status");

    this.container.addEventListener("mousedown", (e) => this._handleMouseDown(e));
    this.container.addEventListener("wheel", (e) => this._handleWheel(e), { passive: false });
    this.container.addEventListener("touchstart", (e) => this._handleTouchStart(e), { passive: false });
    // Attach move/up to window so dragging works even if cursor leaves the container
    window.addEventListener("mousemove", this._onMouseMove);
    window.addEventListener("mouseup", this._onMouseUp);
    window.addEventListener("touchmove", this._onTouchMove, { passive: false });
    window.addEventListener("touchend", this._onTouchEnd);

    this._resizeObserver = new ResizeObserver(() => this._render());
    this._resizeObserver.observe(this.container);

    // Prevent context menu on the map
    this.container.addEventListener("contextmenu", (e) => e.preventDefault());

    this._render();
  },

  destroyed() {
    window.removeEventListener("mousemove", this._onMouseMove);
    window.removeEventListener("mouseup", this._onMouseUp);
    window.removeEventListener("touchmove", this._onTouchMove);
    window.removeEventListener("touchend", this._onTouchEnd);
    this._resizeObserver.disconnect();
  },

  // --- Rendering ---

  _render() {
    // World size in pixels at the current zoom level.
    // At zoom 0 the world is 256px; at zoom z it's 256 * 2^z px.
    const ws = TILE_SIZE * (1 << this.zoom);

    // Number of tiles per axis at this zoom level (2^z)
    const nt = 1 << this.zoom;

    // Viewport (container) dimensions in CSS pixels
    const cw = this.container.clientWidth;
    const ch = this.container.clientHeight;

    // Convert viewport center from world coordinates (0..1) to world pixels,
    // then derive the top-left corner of the visible area in world pixels.
    const centerPxX = this.cx * ws;
    const centerPxY = this.cy * ws;
    const topLeftX = centerPxX - cw / 2;
    const topLeftY = centerPxY - ch / 2;

    // Determine the range of tile indices that overlap the visible area.
    // Each tile covers a TILE_SIZE x TILE_SIZE pixel region in world space.
    let tMinX = Math.floor(topLeftX / TILE_SIZE);
    let tMinY = Math.floor(topLeftY / TILE_SIZE);
    let tMaxX = Math.floor((topLeftX + cw) / TILE_SIZE);
    let tMaxY = Math.floor((topLeftY + ch) / TILE_SIZE);

    // Clamp to the valid tile range [0, nt-1] so we don't request
    // tiles that don't exist (e.g. negative indices or beyond the grid).
    tMinX = Math.max(0, tMinX);
    tMinY = Math.max(0, tMinY);
    tMaxX = Math.min(nt - 1, tMaxX);
    tMaxY = Math.min(nt - 1, tMaxY);

    // Track which tile keys ("z/x/y") are needed this frame,
    // so we can remove stale tiles afterwards.
    const needed = new Set();

    for (let ty = tMinY; ty <= tMaxY; ty++) {
      for (let tx = tMinX; tx <= tMaxX; tx++) {
        const key = `${this.zoom}/${tx}/${ty}`;
        needed.add(key);

        // Reuse cached <img> if we already created one for this tile,
        // otherwise create a new one and start loading it.
        let img = this.tiles.get(key);
        if (!img) {
          img = document.createElement("img");
          img.src = `/tiles/${this.zoom}/${tx}/${ty}/${this.dpr}`;
          img.style.cssText = `position:absolute;width:${TILE_SIZE}px;height:${TILE_SIZE}px;`;
          img.draggable = false;
          this.tileLayer.appendChild(img);
          this.tiles.set(key, img);
        }

        // Position the tile relative to the container's top-left corner.
        // The tile's world-pixel origin is (tx * TILE_SIZE, ty * TILE_SIZE);
        // subtracting topLeft converts to container-local coordinates.
        img.style.left = `${tx * TILE_SIZE - topLeftX}px`;
        img.style.top = `${ty * TILE_SIZE - topLeftY}px`;
      }
    }

    // Remove tiles that are no longer visible (different zoom level
    // or scrolled out of view). This keeps the DOM lean.
    for (const [key, img] of this.tiles) {
      if (!needed.has(key)) {
        img.remove();
        this.tiles.delete(key);
      }
    }

    this._updateStatus();
  },

  _updateStatus() {
    if (!this.statusEl) return;
    // Map viewport center to complex plane (same mapping as server)
    const cr = (-2.5 + this.cx * 3.5).toFixed(10);
    const ci = (-1.75 + this.cy * 3.5).toFixed(10);
    this.statusEl.textContent = `z=${this.zoom}  re=${cr}  im=${ci}`;
  },

  // --- Mouse events ---

  _handleMouseDown(e) {
    if (e.button !== 0) return;
    this.dragging = true;
    this.lastX = e.clientX;
    this.lastY = e.clientY;
    this.container.style.cursor = "grabbing";
    e.preventDefault();
  },

  _handleMouseMove(e) {
    if (!this.dragging) return;
    const dx = e.clientX - this.lastX;
    const dy = e.clientY - this.lastY;
    this.lastX = e.clientX;
    this.lastY = e.clientY;

    const ws = TILE_SIZE * (1 << this.zoom);
    this.cx -= dx / ws;
    this.cy -= dy / ws;
    this._render();
  },

  _handleMouseUp(_e) {
    if (!this.dragging) return;
    this.dragging = false;
    this.container.style.cursor = "grab";
  },

  // --- Wheel zoom (toward cursor) ---

  _handleWheel(e) {
    e.preventDefault();

    // Reset accumulator on direction change
    if ((e.deltaY > 0 && this.scrollAccum < 0) || (e.deltaY < 0 && this.scrollAccum > 0)) {
      this.scrollAccum = 0;
    }
    this.scrollAccum += e.deltaY;

    if (Math.abs(this.scrollAccum) < SCROLL_THRESHOLD) return;

    const zoomDelta = this.scrollAccum > 0 ? -1 : 1;
    this.scrollAccum = 0;

    const rect = this.container.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    const cw = this.container.clientWidth;
    const ch = this.container.clientHeight;

    const ws = TILE_SIZE * (1 << this.zoom);
    const centerPxX = this.cx * ws;
    const centerPxY = this.cy * ws;
    const mouseWorldX = (centerPxX - cw / 2 + mouseX) / ws;
    const mouseWorldY = (centerPxY - ch / 2 + mouseY) / ws;

    const newZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, this.zoom + zoomDelta));
    if (newZoom === this.zoom) return;

    const newWs = TILE_SIZE * (1 << newZoom);
    this.cx = mouseWorldX + (cw / 2 - mouseX) / newWs;
    this.cy = mouseWorldY + (ch / 2 - mouseY) / newWs;
    this.zoom = newZoom;
    this._render();
  },

  // --- Touch events ---

  _handleTouchStart(e) {
    if (e.touches.length === 1) {
      this.dragging = true;
      this.pinchStartDist = null;
      this.lastX = e.touches[0].clientX;
      this.lastY = e.touches[0].clientY;
      e.preventDefault();
    } else if (e.touches.length === 2) {
      this.dragging = false;
      this.pinchStartDist = this._touchDist(e.touches);
      this.pinchStartZoom = this.zoom;
      e.preventDefault();
    }
  },

  _handleTouchMove(e) {
    if (e.touches.length === 1 && this.dragging) {
      const dx = e.touches[0].clientX - this.lastX;
      const dy = e.touches[0].clientY - this.lastY;
      this.lastX = e.touches[0].clientX;
      this.lastY = e.touches[0].clientY;

      const ws = TILE_SIZE * (1 << this.zoom);
      this.cx -= dx / ws;
      this.cy -= dy / ws;
      this._render();
      e.preventDefault();
    } else if (e.touches.length === 2 && this.pinchStartDist) {
      const dist = this._touchDist(e.touches);
      const ratio = dist / this.pinchStartDist;
      const zoomDelta = Math.round(Math.log2(ratio));
      const newZoom = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM,
        this.pinchStartZoom + zoomDelta
      ));
      if (newZoom !== this.zoom) {
        this.zoom = newZoom;
        this._render();
      }
      e.preventDefault();
    }
  },

  _handleTouchEnd(_e) {
    this.dragging = false;
    this.pinchStartDist = null;
  },

  _touchDist(touches) {
    const dx = touches[0].clientX - touches[1].clientX;
    const dy = touches[0].clientY - touches[1].clientY;
    return Math.sqrt(dx * dx + dy * dy);
  },
};

export default MapHook;
