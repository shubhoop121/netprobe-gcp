/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL: string;
  // add more environment variables here if needed, for example:
  // readonly VITE_SOCKET_PORT: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
