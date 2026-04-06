# FRONTEND_PLAN

## Scope
Enterprise-grade frontend for Battery Service & Warranty Management SaaS using only HTML5, CSS3, and Vanilla JS (ES2020), deployable on shared hosting.

## Architecture
- Multi-page HTML structure under `frontend/pages/*`
- Shared shell and partials under `frontend/partials/*`
- Shared CSS architecture under `frontend/assets/css/*`
- Shared JS architecture under `frontend/assets/js/*`
- API-first fetch integration for `/api/v1/*`
- Role-based menu and page guards in frontend

## First Implementation Batch
1. `frontend` folder tree scaffold
2. Shared layout structure (shell/sidebar/topbar/page-header)
3. Role-based sidebar config (`frontend/assets/js/roles.js`)
4. Global CSS architecture (`base.css`, `theme.css`, `layout.css`, `components.css`, `utilities.css`)
5. Global JS architecture (`app.js`, `api.js`, `auth.js`, `ui.js`, `router.js`, `storage.js`)
6. Starter pages:
   - `frontend/pages/admin/dashboard.html`
   - `frontend/pages/dealer/claims-list.html`
   - `frontend/pages/driver/route-today.html`
   - `frontend/pages/crm/dashboard.html`
   - `frontend/pages/tracking/track-token.html`

## AMARON Theme Baseline
- Primary: `#00A651`
- Primary Dark: `#007A3D`
- Primary Light: `#E6F7EF`
- Background: `#F8FAFB`
- Card: `#FFFFFF`
- Border: `#E5E7EB`
- Text: `#1F2937`
- Muted: `#6B7280`
- Warning: `#F59E0B`
- Danger: `#EF4444`
- Info: `#3B82F6`
- Success: `#10B981`
