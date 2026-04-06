export const ROLE_MENU = {
  ADMIN: [
    { label: 'Admin Dashboard', path: 'admin/dashboard.html' },
    { label: 'Service Queue', path: 'admin/service-queue.html' },
    { label: 'Inventory', path: 'admin/inventory-overview.html' },
    { label: 'Claims', path: 'dealer/claims-list.html' },
    { label: 'CRM', path: 'crm/dashboard.html' },
    { label: 'Driver Ops', path: 'driver/route-today.html' },
  ],
  SUPER_MGR: [
    { label: 'Manager Dashboard', path: 'admin/dashboard.html' },
    { label: 'Claims', path: 'dealer/claims-list.html' },
    { label: 'CRM', path: 'crm/dashboard.html' },
  ],
  DISPATCH_MGR: [
    { label: 'Driver Routes', path: 'driver/route-today.html' },
    { label: 'Proof Of Delivery', path: 'driver/proof-of-delivery.html' },
  ],
  DEALER: [
    { label: 'My Claims', path: 'dealer/claims-list.html' },
    { label: 'Create Claim', path: 'dealer/new-claim.html' },
  ],
  DRIVER: [
    { label: 'Today Route', path: 'driver/route-today.html' },
    { label: 'Proof Of Delivery', path: 'driver/proof-of-delivery.html' },
  ],
  TESTER: [
    { label: 'Service Queue', path: 'admin/service-queue.html' },
  ],
  INV_MGR: [
    { label: 'Inventory', path: 'admin/inventory-overview.html' },
  ],
  CRM_MGR: [
    { label: 'CRM Dashboard', path: 'crm/dashboard.html' },
    { label: 'Customers', path: 'crm/customers.html' },
  ],
  MARKETING: [
    { label: 'Campaign Analytics', path: 'crm/dashboard.html' },
    { label: 'Customers', path: 'crm/customers.html' },
  ],
};

export const PAGE_PERMISSIONS = {
  'admin-dashboard': ['ADMIN', 'SUPER_MGR'],
  'service-queue': ['ADMIN', 'TESTER'],
  'inventory-overview': ['ADMIN', 'INV_MGR'],
  'dealer-claims': ['ADMIN', 'SUPER_MGR', 'DEALER'],
  'dealer-new-claim': ['DEALER'],
  'driver-route': ['ADMIN', 'SUPER_MGR', 'DISPATCH_MGR', 'DRIVER'],
  'driver-pod': ['DISPATCH_MGR', 'DRIVER'],
  'crm-dashboard': ['ADMIN', 'SUPER_MGR', 'CRM_MGR', 'MARKETING'],
  'crm-customers': ['CRM_MGR', 'MARKETING'],
  'public-track': ['PUBLIC'],
};
