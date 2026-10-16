import { useState } from 'preact/hooks';

const MAX = 900;

/** Shrinks a photo on the phone before upload: 900px WebP, usually under 100 KB. */
async function shrink(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, MAX / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext('2d')!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/webp', 0.8));
  // Some older phones can't make WebP; JPEG works everywhere.
  if (blob && blob.type === 'image/webp') return blob;
  return new Promise((resolve) => canvas.toBlob((b) => resolve(b!), 'image/jpeg', 0.85));
}

export default function PhotoUpload({ productId }: { productId: string }) {
  const [busy, setBusy] = useState('');
  const [error, setError] = useState('');

  async function upload(files: FileList | null) {
    if (!files?.length) return;
    setError('');
    try {
      for (const [i, file] of [...files].slice(0, 8).entries()) {
        setBusy(`Uploading ${i + 1} of ${Math.min(files.length, 8)}…`);
        const blob = await shrink(file);
        const res = await fetch(`/api/admin/photos?product=${encodeURIComponent(productId)}`, {
          method: 'POST',
          headers: { 'Content-Type': blob.type },
          body: blob,
        });
        if (!res.ok) throw new Error(((await res.json()) as { error?: string }).error ?? 'Upload failed');
      }
      window.location.href = `${window.location.pathname}?ok=${encodeURIComponent('Photos added')}#photos`;
    } catch (e) {
      setBusy('');
      setError(e instanceof Error ? e.message : 'Upload failed');
    }
  }

  return (
    <div>
      <label class={`btn-outline cursor-pointer ${busy ? 'pointer-events-none opacity-60' : ''}`}>
        <input type="file" accept="image/*" multiple class="sr-only" onChange={(e) => upload(e.currentTarget.files)} />
        {busy || 'Add photos'}
      </label>
      {error && <p role="alert" class="mt-2 text-sm font-semibold text-sale">{error}</p>}
    </div>
  );
}
