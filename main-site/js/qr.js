// A small QR encoder, so the pairing code can be scanned with no network
// and no third party script. Byte mode, error correction level M, smallest
// version that fits the URL, which for our short links is version 2 to 4.
//
// This is a standard QR implementation: Reed-Solomon over GF(256), the
// fixed function patterns, then the eight masks scored by the penalty rules
// in the spec. It is here rather than from a CDN so the code for syncing
// boards draws without a third party. Ported from sgbus-timings, from uwuPromptr.
// Plain script: this project does not use ES modules, so exports go on window.
(function () {
  // Lookup tables for arithmetic in the Galois field GF(256): powers of 2, and their inverse
  // (the logarithm of each value). The powers table is doubled in length so that adding two
  // logarithms never needs wrapping round.
  const GALOIS_FIELD_EXPONENTS = new Uint8Array(512);
  const GALOIS_FIELD_LOGARITHMS = new Uint8Array(256);

  (function buildTables() {
    let value = 1;
    for (let power = 0; power < 255; power = power + 1) {
      GALOIS_FIELD_EXPONENTS[power] = value;
      GALOIS_FIELD_LOGARITHMS[value] = power;
      value = value << 1;
      if (value & 0x100) {
        value = value ^ 0x11d;
      }
    }
    for (let power = 255; power < 512; power = power + 1) {
      GALOIS_FIELD_EXPONENTS[power] = GALOIS_FIELD_EXPONENTS[power - 255];
    }
  })();

  // Multiplies two numbers in GF(256), using the logarithm tables above.
  function galoisMultiply(left, right) {
    if (left === 0 || right === 0) {
      return 0;
    }
    return GALOIS_FIELD_EXPONENTS[GALOIS_FIELD_LOGARITHMS[left] + GALOIS_FIELD_LOGARITHMS[right]];
  }

  // The Reed-Solomon generator polynomial for `degree` error correction codewords, as its
  // list of coefficients.
  function reedSolomonGeneratorPolynomial(degree) {
    let polynomial = [1];
    for (let termIndex = 0; termIndex < degree; termIndex = termIndex + 1) {
      const next = new Array(polynomial.length + 1).fill(0);
      for (let coefficientIndex = 0; coefficientIndex < polynomial.length; coefficientIndex = coefficientIndex + 1) {
        next[coefficientIndex] = next[coefficientIndex] ^ polynomial[coefficientIndex];
        next[coefficientIndex + 1] = next[coefficientIndex + 1] ^ galoisMultiply(polynomial[coefficientIndex], GALOIS_FIELD_EXPONENTS[termIndex]);
      }
      polynomial = next;
    }
    return polynomial;
  }

  // The error correction codewords for one block of data: the remainder of dividing the data
  // by the generator polynomial.
  function reedSolomonEncode(data, errorCorrectionCount) {
    const generator = reedSolomonGeneratorPolynomial(errorCorrectionCount);
    const result = new Array(errorCorrectionCount).fill(0);

    for (const byte of data) {
      const factor = byte ^ result[0];
      result.shift();
      result.push(0);
      for (let index = 0; index < errorCorrectionCount; index = index + 1) {
        result[index] = result[index] ^ galoisMultiply(generator[index + 1], factor);
      }
    }
    return result;
  }

  // Per version, error correction level M: total codewords, EC codewords per
  // block, block counts. Versions 1 to 9, which holds 182 bytes at level M and
  // is far more than a pairing URL needs. The ceiling is 9 rather than a
  // rounder number because byte mode switches from an 8 bit character count to
  // a 16 bit one at version 10, and buildBitStream below writes the 8 bit one.
  const VERSIONS = {
    1: { total: 26, errorCorrection: 10, groups: [[1, 16]] },
    2: { total: 44, errorCorrection: 16, groups: [[1, 28]] },
    3: { total: 70, errorCorrection: 26, groups: [[1, 44]] },
    4: { total: 100, errorCorrection: 18, groups: [[2, 32]] },
    5: { total: 134, errorCorrection: 24, groups: [[2, 43]] },
    6: { total: 172, errorCorrection: 16, groups: [[4, 27]] },
    7: { total: 196, errorCorrection: 18, groups: [[4, 31]] },
    8: { total: 242, errorCorrection: 22, groups: [[2, 38], [2, 39]] },
    9: { total: 292, errorCorrection: 22, groups: [[3, 36], [2, 37]] },
  };

  const MAX_VERSION = 9;

  const ALIGNMENT_CENTRES = {
    1: [],
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50],
  };

  // Format information for level M and each mask, already BCH-encoded and
  // XOR-masked, which is the whole table rather than re-deriving it.
  const FORMAT_BITS = [
    0x5412, 0x5125, 0x5e7c, 0x5b4b, 0x45f9, 0x40ce, 0x4f97, 0x4aa0,
  ];

  // Version information, BCH(18,6). Only versions 7 and up carry it, in two
  // 6x3 blocks beside the lower-left and upper-right finders. Leaving it out
  // does not just omit a decoration: those cells are reserved, so data bits
  // land in them and the whole symbol stops decoding.
  const VERSION_BITS = {
    7: 0x07c94,
    8: 0x085bc,
    9: 0x09a99,
  };

  // How many data codewords a version holds: the blocks in each group times their size.
  function dataCodewordCount(info) {
    return info.groups.reduce((sum, [count, size]) => {
      return sum + count * size;
    }, 0);
  }

  // The smallest version whose data codewords fit `byteLength` bytes, or null if none does.
  function chooseVersion(byteLength) {
    for (let version = 1; version <= MAX_VERSION; version = version + 1) {
      const info = VERSIONS[version];
      const dataCodewords = dataCodewordCount(info);
      // Mode indicator plus the character count indicator: 4 bits then 8,
      // which is a byte and a half, so two whole codewords of overhead.
      const needed = byteLength + 2;
      if (dataCodewords >= needed) {
        return version;
      }
    }
    return null;
  }

  // The data codewords for `bytes`: the byte mode header, the bytes themselves, a terminator,
  // and padding up to the version's capacity.
  function buildBitStream(bytes, version) {
    const info = VERSIONS[version];
    const dataCodewords = dataCodewordCount(info);
    const bits = [];

    const push = (value, length) => {
      for (let bitIndex = length - 1; bitIndex >= 0; bitIndex = bitIndex - 1) {
        bits.push((value >> bitIndex) & 1);
      }
    };

    push(0b0100, 4); // byte mode
    // Byte mode's character count is 8 bits up to version 9 and 16 from
    // version 10, which is why chooseVersion stops at MAX_VERSION.
    push(bytes.length, 8);
    for (const byte of bytes) {
      push(byte, 8);
    }

    // Terminator, then pad to a byte boundary.
    const capacity = dataCodewords * 8;
    for (let zeroCount = 0; zeroCount < 4 && bits.length < capacity; zeroCount = zeroCount + 1) {
      bits.push(0);
    }
    while (bits.length % 8 !== 0) {
      bits.push(0);
    }

    const codewords = [];
    for (let byteStart = 0; byteStart < bits.length; byteStart = byteStart + 8) {
      let byte = 0;
      for (let bitOffset = 0; bitOffset < 8; bitOffset = bitOffset + 1) {
        byte = (byte << 1) | bits[byteStart + bitOffset];
      }
      codewords.push(byte);
    }

    // The two alternating pad codewords the spec names.
    const PAD_CODEWORDS = [0xec, 0x11];
    let padIndex = 0;
    while (codewords.length < dataCodewords) {
      const thisPadIndex = padIndex;
      padIndex = padIndex + 1;
      codewords.push(PAD_CODEWORDS[thisPadIndex % 2]);
    }

    return codewords;
  }

  // Splits the data codewords into the version's blocks, adds each block's error correction,
  // then weaves the blocks together codeword by codeword as the spec lays them out.
  function interleave(codewords, version) {
    const info = VERSIONS[version];
    const blocks = [];
    let offset = 0;

    for (const [count, size] of info.groups) {
      for (let blockNumber = 0; blockNumber < count; blockNumber = blockNumber + 1) {
        const data = codewords.slice(offset, offset + size);
        offset = offset + size;
        blocks.push({ data, errorCorrection: reedSolomonEncode(data, info.errorCorrection) });
      }
    }

    const result = [];
    const maxData = Math.max(...blocks.map((block) => {
      return block.data.length;
    }));
    for (let index = 0; index < maxData; index = index + 1) {
      for (const block of blocks) {
        if (index < block.data.length) {
          result.push(block.data[index]);
        }
      }
    }
    for (let index = 0; index < info.errorCorrection; index = index + 1) {
      for (const block of blocks) {
        result.push(block.errorCorrection[index]);
      }
    }
    return result;
  }

  // An empty symbol for `version` with its fixed patterns drawn in (finders, timing,
  // alignment, the dark module) and the cells they and the format/version information use
  // marked as reserved, so the data goes everywhere else.
  function createMatrix(version) {
    const size = version * 4 + 17;
    const modules = Array.from({ length: size }, () => {
      return new Array(size).fill(null);
    });
    const reserved = Array.from({ length: size }, () => {
      return new Array(size).fill(false);
    });

    const setFixed = (row, column, value) => {
      modules[row][column] = value;
      reserved[row][column] = true;
    };

    // Finder patterns and their separators.
    const placeFinder = (top, left) => {
      for (let rowOffset = -1; rowOffset <= 7; rowOffset = rowOffset + 1) {
        for (let columnOffset = -1; columnOffset <= 7; columnOffset = columnOffset + 1) {
          const row = top + rowOffset;
          const column = left + columnOffset;
          if (row < 0 || row >= size || column < 0 || column >= size) {
            continue;
          }
          const onRing = (rowOffset >= 0 && rowOffset <= 6 && (columnOffset === 0 || columnOffset === 6)) ||
            (columnOffset >= 0 && columnOffset <= 6 && (rowOffset === 0 || rowOffset === 6));
          const inCore = rowOffset >= 2 && rowOffset <= 4 && columnOffset >= 2 && columnOffset <= 4;
          if (onRing || inCore) {
            setFixed(row, column, 1);
          } else {
            setFixed(row, column, 0);
          }
        }
      }
    };

    placeFinder(0, 0);
    placeFinder(0, size - 7);
    placeFinder(size - 7, 0);

    // Timing patterns.
    for (let position = 8; position < size - 8; position = position + 1) {
      let timingValue;
      if (position % 2 === 0) {
        timingValue = 1;
      } else {
        timingValue = 0;
      }
      setFixed(6, position, timingValue);
      setFixed(position, 6, timingValue);
    }

    // Alignment patterns, skipping the three that would sit on a finder.
    const centres = ALIGNMENT_CENTRES[version];
    for (const row of centres) {
      for (const column of centres) {
        const onFinder =
          (row <= 8 && column <= 8) ||
          (row <= 8 && column >= size - 9) ||
          (row >= size - 9 && column <= 8);
        if (onFinder) {
          continue;
        }
        for (let rowOffset = -2; rowOffset <= 2; rowOffset = rowOffset + 1) {
          for (let columnOffset = -2; columnOffset <= 2; columnOffset = columnOffset + 1) {
            const ring = Math.max(Math.abs(rowOffset), Math.abs(columnOffset));
            if (ring === 1) {
              setFixed(row + rowOffset, column + columnOffset, 0);
            } else {
              setFixed(row + rowOffset, column + columnOffset, 1);
            }
          }
        }
      }
    }

    // Version information areas, reserved here and filled in writeFormat.
    if (version >= 7) {
      for (let index = 0; index < 18; index = index + 1) {
        const row = Math.floor(index / 3);
        const column = index % 3;
        setFixed(size - 11 + column, row, 0);
        setFixed(row, size - 11 + column, 0);
      }
    }

    // The dark module, and the format information areas held back.
    setFixed(size - 8, 8, 1);
    for (let index = 0; index < 9; index = index + 1) {
      if (modules[8][index] === null) { modules[8][index] = 0; reserved[8][index] = true; }
      if (modules[index][8] === null) { modules[index][8] = 0; reserved[index][8] = true; }
    }
    for (let index = 0; index < 8; index = index + 1) {
      if (modules[8][size - 1 - index] === null) { modules[8][size - 1 - index] = 0; reserved[8][size - 1 - index] = true; }
      if (modules[size - 1 - index][8] === null) { modules[size - 1 - index][8] = 0; reserved[size - 1 - index][8] = true; }
    }

    return { modules, reserved, size };
  }

  // Lays the codewords' bits into every cell that isn't reserved, in the spec's zigzag: two
  // columns at a time from the right, alternately going up and down.
  function placeData(matrix, codewords) {
    const { modules, reserved, size } = matrix;
    const bits = [];
    for (const byte of codewords) {
      for (let bitIndex = 7; bitIndex >= 0; bitIndex = bitIndex - 1) {
        bits.push((byte >> bitIndex) & 1);
      }
    }

    let index = 0;
    let upward = true;

    for (let right = size - 1; right > 0; right = right - 2) {
      // Column 6 is the vertical timing pattern and is not part of the zigzag.
      if (right === 6) {
        right = 5;
      }

      for (let step = 0; step < size; step = step + 1) {
        let row;
        if (upward) {
          row = size - 1 - step;
        } else {
          row = step;
        }
        for (const column of [right, right - 1]) {
          if (reserved[row][column]) {
            continue;
          }
          if (index < bits.length) {
            modules[row][column] = bits[index];
            index = index + 1;
          } else {
            modules[row][column] = 0;
          }
        }
      }
      upward = !upward;
    }
  }

  // Whether mask pattern number `mask` flips the cell at `row`, `column`.
  function maskBit(mask, row, column) {
    switch (mask) {
      case 0: return (row + column) % 2 === 0;
      case 1: return row % 2 === 0;
      case 2: return column % 3 === 0;
      case 3: return (row + column) % 3 === 0;
      case 4: return (Math.floor(row / 2) + Math.floor(column / 3)) % 2 === 0;
      case 5: return ((row * column) % 2) + ((row * column) % 3) === 0;
      case 6: return (((row * column) % 2) + ((row * column) % 3)) % 2 === 0;
      default: return (((row + column) % 2) + ((row * column) % 3)) % 2 === 0;
    }
  }

  // A copy of the symbol's cells with mask pattern `mask` applied to the data cells.
  function applyMask(matrix, mask) {
    const { modules, reserved, size } = matrix;
    const masked = modules.map((row) => {
      return row.slice();
    });
    for (let row = 0; row < size; row = row + 1) {
      for (let column = 0; column < size; column = column + 1) {
        if (reserved[row][column]) {
          continue;
        }
        if (maskBit(mask, row, column)) {
          masked[row][column] = masked[row][column] ^ 1;
        }
      }
    }
    return masked;
  }

  function writeVersion(grid, size, version) {
    if (version < 7) {
      return;
    }
    const bits = VERSION_BITS[version];

    // Least significant bit first, down the three columns beside the
    // lower-left finder and mirrored beside the upper-right one.
    for (let index = 0; index < 18; index = index + 1) {
      const bit = (bits >> index) & 1;
      const row = Math.floor(index / 3);
      const column = index % 3;
      grid[size - 11 + column][row] = bit;
      grid[row][size - 11 + column] = bit;
    }
  }

  // Writes the format information for `mask` in its two places: around the top-left finder,
  // and split between the bottom-left and top-right ones.
  function writeFormat(grid, size, mask) {
    const bits = FORMAT_BITS[mask];
    // The format word is placed most significant bit first: index 0 below is
    // bit 14 of the word, not bit 0. Indexing it the other way round produces
    // a symbol that looks perfectly well formed and decodes to nothing.
    const formatBit = (position) => {
      return (bits >> (14 - position)) & 1;
    };

    for (let position = 0; position <= 5; position = position + 1) {
      grid[8][position] = formatBit(position);
    }
    grid[8][7] = formatBit(6);
    grid[8][8] = formatBit(7);
    grid[7][8] = formatBit(8);
    for (let position = 9; position <= 14; position = position + 1) {
      grid[14 - position][8] = formatBit(position);
    }

    for (let position = 0; position <= 7; position = position + 1) {
      grid[size - 1 - position][8] = formatBit(position);
    }
    for (let position = 8; position <= 14; position = position + 1) {
      grid[8][size - 15 + position] = formatBit(position);
    }

    grid[size - 8][8] = 1;
  }

  // The spec's penalty score for a masked symbol: lower is easier for a scanner to read, and
  // the mask with the lowest score is the one used.
  function penalty(grid, size) {
    let score = 0;

    // Rule 1: runs of five or more of the same colour.
    const runScore = (line) => {
      let total = 0;
      let run = 1;
      for (let index = 1; index < line.length; index = index + 1) {
        if (line[index] === line[index - 1]) {
          run = run + 1;
        } else {
          if (run >= 5) {
            total = total + (3 + (run - 5));
          }
          run = 1;
        }
      }
      if (run >= 5) {
        total = total + (3 + (run - 5));
      }
      return total;
    };

    // The cells of one column, top to bottom.
    const columnOf = (column) => {
      return grid.map((row) => {
        return row[column];
      });
    };

    for (let row = 0; row < size; row = row + 1) {
      score = score + runScore(grid[row]);
    }
    for (let column = 0; column < size; column = column + 1) {
      score = score + runScore(columnOf(column));
    }

    // Rule 2: 2x2 blocks of one colour.
    for (let row = 0; row < size - 1; row = row + 1) {
      for (let column = 0; column < size - 1; column = column + 1) {
        const colour = grid[row][column];
        if (colour === grid[row][column + 1] && colour === grid[row + 1][column] && colour === grid[row + 1][column + 1]) {
          score = score + 3;
        }
      }
    }

    // Rule 3: the finder-like 1011101 pattern with four light modules beside it.
    const PATTERN = [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0];
    const REVERSED = [...PATTERN].reverse();
    const hasAt = (line, start, pattern) => {
      return pattern.every((patternValue, offset) => {
        return line[start + offset] === patternValue;
      });
    };

    const patternScore = (line) => {
      let total = 0;
      for (let start = 0; start + PATTERN.length <= line.length; start = start + 1) {
        if (hasAt(line, start, PATTERN) || hasAt(line, start, REVERSED)) {
          total = total + 40;
        }
      }
      return total;
    };

    for (let row = 0; row < size; row = row + 1) {
      score = score + patternScore(grid[row]);
    }
    for (let column = 0; column < size; column = column + 1) {
      score = score + patternScore(columnOf(column));
    }

    // Rule 4: deviation from an even split of dark and light.
    let dark = 0;
    for (let row = 0; row < size; row = row + 1) {
      for (let column = 0; column < size; column = column + 1) {
        dark = dark + grid[row][column];
      }
    }
    const ratio = (dark * 100) / (size * size);
    score = score + Math.floor(Math.abs(ratio - 50) / 5) * 10;

    return score;
  }

  // Returns { size, modules } where modules is a size x size array of 0/1,
  // or null if the text is too long for version 9 at level M.
  function encodeQr(text) {
    const bytes = new TextEncoder().encode(text);
    const version = chooseVersion(bytes.length);
    if (!version) {
      return null;
    }

    const codewords = interleave(buildBitStream(bytes, version), version);
    const matrix = createMatrix(version);
    placeData(matrix, codewords);

    let best = null;
    for (let mask = 0; mask < 8; mask = mask + 1) {
      const grid = applyMask(matrix, mask);
      writeFormat(grid, matrix.size, mask);
      writeVersion(grid, matrix.size, version);
      const score = penalty(grid, matrix.size);
      if (!best || score < best.score) {
        best = { score, grid };
      }
    }

    return { size: matrix.size, modules: best.grid };
  }

  // One path for every dark module, which keeps the SVG small enough to set
  // as innerHTML without a second thought.
  function qrToSvg(text, { quiet: quietZone = 4 } = {}) {
    const code = encodeQr(text);
    if (!code) {
      return "";
    }

    const span = code.size + quietZone * 2;
    let path = "";

    for (let row = 0; row < code.size; row = row + 1) {
      for (let column = 0; column < code.size; column = column + 1) {
        if (code.modules[row][column]) {
          path = path + `M${column + quietZone} ${row + quietZone}h1v1h-1z`;
        }
      }
    }

    return `<svg viewBox="0 0 ${span} ${span}" shape-rendering="crispEdges" role="img" aria-label="QR code of the sync link">
      <rect class="qr-bg" width="${span}" height="${span}" rx="1"/>
      <path class="qr-fg" d="${path}"/>
    </svg>`;
  }

  window.qrToSvg = qrToSvg;
})();
