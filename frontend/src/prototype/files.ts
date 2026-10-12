function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open('docaya-prototype-files', 1)
    request.onupgradeneeded = () => request.result.createObjectStore('files')
    request.onsuccess = () => resolve(request.result)
    request.onerror = () => reject(request.error)
  })
}
export async function saveOriginal(id: string, file: File) {
  const db = await database()
  try {
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('files', 'readwrite')
      tx.objectStore('files').put(file, id)
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
      tx.onabort = () => reject(tx.error)
    })
  } finally {
    db.close()
  }
}
export async function readOriginal(id: string): Promise<File | undefined> {
  const db = await database()
  try {
    return await new Promise((resolve, reject) => {
      const request = db.transaction('files').objectStore('files').get(id)
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => reject(request.error)
    })
  } finally {
    db.close()
  }
}
export async function clearOriginals() {
  const db = await database()
  try {
    await new Promise<void>((resolve, reject) => {
      const tx = db.transaction('files', 'readwrite')
      tx.objectStore('files').clear()
      tx.oncomplete = () => resolve()
      tx.onerror = () => reject(tx.error)
    })
  } finally {
    db.close()
  }
}
export async function fingerprint(file: File) {
  const data = new Uint8Array(await file.arrayBuffer())
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', data)))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  const ext = file.name.split('.').at(-1)?.toLowerCase()
  const signature = Array.from(data.slice(0, 4))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  const valid =
    ext === 'pdf'
      ? signature === '25504446'
      : ['docx', 'xlsx', 'pptx'].includes(ext || '')
        ? signature === '504b0304'
        : ext === 'png'
          ? signature === '89504e47'
          : ['jpg', 'jpeg'].includes(ext || '')
            ? signature.startsWith('ffd8ff')
            : ext === 'tiff' || ext === 'tif'
              ? ['49492a00', '4d4d002a'].includes(signature)
              : ext === 'txt'
  if (!valid)
    throw new Error('File signature does not match an accepted format / توقيع الملف لا يطابق صيغة مقبولة')
  return hash
}
