// @ts-check
import { defineConfig, envField } from 'astro/config';
import cloudflare from '@astrojs/cloudflare';
import preact from '@astrojs/preact';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  // Pages are rendered on Cloudflare at request time so prices and stock are
  // always current; responses are cached briefly (see src/lib/http.ts).
  output: 'server',
  // Photos are resized in the admin app before upload, so no paid image
  // service is needed; the shop keeps no server sessions either.
  adapter: cloudflare({ imageService: 'passthrough' }),
  session: false,
  integrations: [preact()],
  vite: { plugins: [tailwindcss()] },
  env: {
    schema: {
      SUPABASE_URL: envField.string({ context: 'server', access: 'secret', optional: true }),
      SUPABASE_ANON_KEY: envField.string({ context: 'server', access: 'secret', optional: true }),
      // Tests and local previews only: serve the built-in test catalog.
      SHOP_DATA: envField.enum({ context: 'server', access: 'secret', values: ['supabase', 'fixtures'], optional: true }),
    },
  },
});
