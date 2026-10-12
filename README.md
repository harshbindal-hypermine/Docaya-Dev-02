# Docaya Full Stack

This repository combines:

- `frontend/` — React/Vite frontend copied from the original frontend folder.
- `backend/` — backend-only code copied from the original backend folder. The backend folder's embedded web/frontend package was intentionally excluded.

## Run locally

### Frontend

```bash
cd frontend
npm install
npm run dev
```

The Vite dev server proxies `/api` and `/health` to the backend API URL configured by `DOCAYA_API_PROXY` or `http://localhost:8787` by default.

### Backend API

```bash
dotnet run --project backend/api/Docaya.Api/Docaya.Api.csproj
```

### Backend Functions

```bash
dotnet build backend/functions/Docaya.Functions.sln
```

## Build all

```bash
npm run build
```
