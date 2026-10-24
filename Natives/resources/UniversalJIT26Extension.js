logLevel = LOG_INFO;
let detachAfterFirstBr = false;

// CubeXCraft: регион кода JVM. StikDebug (prepare_memory_region) пишет адрес страницы 9 hex-цифрами, поэтому регион
// выше 64 ГБ готовит мимо, и JVM падает с SIGBUS на первом же коде. Такой регион готовим сами, по странице за команду
// (медленнее, но верно). Приложение просит регион заранее (команда 5) — сразу после того, как отпустило свой низкий
// участок адресов, — и он отдаётся JVM на brk 0x69.
const CXC_PREPARE_LIMIT = 0x1000000000n;
let cxcRegion = 0n, cxcRegionSize = 0n;

function cxcAllocRegion(size) {
    let resp = send_command(`_M${size.toString(16)},rx`);
    if (!resp || resp.length === 0 || resp[0] === 'E') {
        log(`[CXC] RX allocation failed: ${resp}`);
        return 0n;
    }
    let addr = BigInt(`0x${resp}`);
    if (addr + size <= CXC_PREPARE_LIMIT) {
        prepare_memory_region(addr, size);
    } else {
        log(`[CXC] region 0x${addr.toString(16)} is above 64 GB, preparing page by page`);
        for (let page = addr; page < addr + size; page += 0x4000n) {
            send_command(`M${page.toString(16)},1:69`);
        }
    }
    log(`[CXC] JIT region 0x${addr.toString(16)}, ${size / 0x100000n} MB`);
    return addr;
}

function cxcReturn(addr) {
    send_command(`P0=${numberToLittleEndianHexString(addr)};thread:${tid};`);
}

// void* CXCBreakAllocJITRegion(void *unused, size_t len)
commands[5] = function(brkResponse) {
    cxcRegion = cxcAllocRegion(x1);
    cxcRegionSize = cxcRegion ? x1 : 0n;
    cxcReturn(cxcRegion);
};

// brk 0x69: char* BreakGetJITMapping(size_t bytes) — регион, выделенный заранее, иначе новый
legacyCommands[0x69] = function(brkResponse) {
    let bytes = x0;
    let addr = cxcRegion;
    if (!addr || bytes > cxcRegionSize) {
        if (addr) {
            send_command(`_m${addr.toString(16)}`);
        }
        addr = cxcAllocRegion(bytes);
    }
    cxcRegion = 0n;
    cxcRegionSize = 0n;
    cxcReturn(addr);
    if (detachAfterFirstBr) {
        JIT26Detach();
    }
};

// JIT26SetDetachAfterFirstBr(BOOL)
commands[3] = function(brkResponse) {
    detachAfterFirstBr = x0 != 0;
    log(`JIT26SetDetachAfterFirstBr(${detachAfterFirstBr}) called`);
};

// JIT26PrepareRegionForPatching(void *addr, size_t len)
commands[4] = function(brkResponse) {
    let x0str = x0.toString(16);
    let x1str = x1.toString(16);
    let bytes = send_command(`m${x0str},${x1str}`);
    send_command(`M${x0str},${x1str}:${bytes}`);
};
