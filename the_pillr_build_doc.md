# The Pillr — Complete Build Documentation
### Flutter + Firebase | Multi-Tenant Church Partnership Management System
### Master Reference for Cursor AI

---

> **Context for Cursor:** This document contains everything needed to build The Pillr application from scratch. Read every section carefully before writing any code. The entire product brief, architecture decisions, data models, UI/UX specifications, role-based access rules, and phased implementation plan are all here. Do not skip sections. Build phase by phase in order.

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Design Philosophy & UI Reference](#2-design-philosophy--ui-reference)
3. [Tech Stack & Architecture Decisions](#3-tech-stack--architecture-decisions)
4. [Multi-Tenancy Architecture](#4-multi-tenancy-architecture)
5. [Authentication & Invite System](#5-authentication--invite-system)
6. [User Roles & Permissions](#6-user-roles--permissions)
7. [Data Models (Firestore)](#7-data-models-firestore)
8. [Firestore Security Rules](#8-firestore-security-rules)
9. [Feature Specifications](#9-feature-specifications)
10. [UI/UX Specifications](#10-uiux-specifications)
11. [Export System](#11-export-system)
12. [Notification System](#12-notification-system)
13. [Phase 1 — Foundation](#13-phase-1--foundation)
14. [Phase 2 — Core Features](#14-phase-2--core-features)
15. [Phase 3 — Roles, Dashboards & Leaderboard](#15-phase-3--roles-dashboards--leaderboard)
16. [Phase 4 — Polish & Excellence](#16-phase-4--polish--excellence)
17. [Project Structure](#17-project-structure)
18. [Environment & Configuration](#18-environment--configuration)
19. [Original Design Conversation](#19-original-design-conversation)

---

## 1. Product Overview

### What Is The Pillr?

**The Pillr** is a multi-tenant church partnership management system. It allows churches to record, manage, track, and report on financial partnership contributions (giving) made by church members.

The flow of a partnership record is:

```
Member gives cash/pledge
    ↓
Church Staff records the entry in the app
    ↓
Pastor receives notification and reviews the entry
    ↓
Pastor approves or declines
    ↓
If approved → Entry is counted in totals, goals, and leaderboard
```

### Core Concepts

| Term | Definition |
|---|---|
| **Church (Tenant)** | A single church organization. Each church is fully isolated from others. |
| **Partner** | A church member who gives. Has a profile with contact and fellowship info. |
| **Partnership Arm** | A category of giving (e.g. Venue, Rhapsody). Multiple arms exist. Each is togglable. |
| **Partnership Period** | A time window for giving (e.g. Q1 2025, Annual 2025). Only ONE period active at a time. |
| **Entry** | A single recorded giving event — links a partner, arm, period, amount, and date. |
| **Approval** | The Pastor's sign-off on an entry. Only approved entries count toward totals and leaderboard. |
| **Goal** | A target amount set by the Pastor per period per arm. |
| **Leaderboard** | A ranked view of partners by total approved giving. Visible only to Pastor and Staff. |

---

## 2. Design Philosophy & UI Reference

### Visual Design Reference Images

Three reference screenshots define the master UI aesthetic:

**Reference 1 — Employee Management System (Notion-like)**
- Clean white background
- Tabbed navigation inside content areas
- Inline data tables with colored status badges
- Subtle row-expand behavior
- Minimal chrome, maximum data density
- Monochrome icons with colored accent dots

**Reference 2 — Brightly Attendance Dashboard**
- Left sidebar with icon + label navigation
- Top stat cards in a 4-column grid layout (white cards, subtle shadow, percentage change indicator)
- Clean data table with avatar/photo in rows
- Status pills (green "On time", red "Late")
- Pagination at the bottom of tables
- Profile avatar + notification bell in top right
- Soft gray page background (#F5F6FA or similar)

**Reference 3 — Zendenta Stock Management**
- Collapsible left sidebar with grouped navigation sections
- Top bar with global search, action buttons, breadcrumb area, user profile
- Large numeric stats with horizontal color-coded progress bar
- Tabbed content switching
- Action buttons are prominent (dark pill button)
- Status badges inline in table rows
- Progress bars within table cells

### Master Design System

#### Color Palette
```dart
// Primary Brand
const Color primaryColor = Color(0xFF1A56DB);        // Deep blue - primary actions
const Color primaryLight = Color(0xFFEBF0FF);        // Light blue - backgrounds, highlights
const Color primaryDark = Color(0xFF1240A8);         // Dark blue - hover states

// Semantic Colors
const Color successColor = Color(0xFF0E9F6E);        // Green - approved, active, on time
const Color successLight = Color(0xFFDEF7EC);        // Light green - success backgrounds
const Color warningColor = Color(0xFFE3A008);        // Amber - pending, warning states
const Color warningLight = Color(0xFFFDF3DC);        // Light amber - warning backgrounds
const Color dangerColor = Color(0xFFE02424);         // Red - declined, inactive, late
const Color dangerLight = Color(0xFFFDE8E8);         // Light red - danger backgrounds
const Color infoColor = Color(0xFF3F83F8);           // Light blue - info states

// Neutrals
const Color gray50 = Color(0xFFF9FAFB);             // Page background
const Color gray100 = Color(0xFFF3F4F6);            // Card/surface backgrounds
const Color gray200 = Color(0xFFE5E7EB);            // Borders, dividers
const Color gray400 = Color(0xFF9CA3AF);            // Placeholder text, icons
const Color gray600 = Color(0xFF4B5563);            // Secondary text
const Color gray900 = Color(0xFF111827);            // Primary text, headings

// Surface
const Color white = Color(0xFFFFFFFF);              // Cards, sidebar
const Color surfaceColor = Color(0xFFF9FAFB);       // Page background
```

#### Typography
```dart
// Font Family: Inter (Google Fonts)
// Import: google_fonts package

// Type Scale
// Display: 32px, weight 700, gray900
// Heading 1: 24px, weight 700, gray900
// Heading 2: 20px, weight 600, gray900
// Heading 3: 16px, weight 600, gray900
// Body Large: 16px, weight 400, gray600
// Body: 14px, weight 400, gray600
// Caption: 12px, weight 400, gray400
// Label: 12px, weight 600, gray600, letter-spacing 0.5
```

#### Spacing System
```dart
// Base unit: 4px
const double xs = 4.0;
const double sm = 8.0;
const double md = 16.0;
const double lg = 24.0;
const double xl = 32.0;
const double xxl = 48.0;
const double xxxl = 64.0;
```

#### Border Radius
```dart
const double radiusXs = 4.0;
const double radiusSm = 6.0;
const double radiusMd = 8.0;
const double radiusLg = 12.0;
const double radiusXl = 16.0;
const double radiusFull = 999.0;  // Fully rounded pills
```

#### Elevation / Shadows
```dart
// Card shadow
BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))
BoxShadow(color: Color(0x06000000), blurRadius: 4, offset: Offset(0, 1))

// Dropdown shadow
BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8))
BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))
```

### Layout Structure

#### Desktop Web (>= 1024px)
```
┌─────────────────────────────────────────────────────┐
│  SIDEBAR (240px fixed)  │  MAIN CONTENT AREA         │
│                         │                            │
│  [Logo + Church Name]   │  [Top Bar]                 │
│                         │  [Page Content]            │
│  [Nav Items]            │                            │
│                         │                            │
│  [User Profile]         │                            │
└─────────────────────────────────────────────────────┘
```

#### Tablet (768px - 1023px)
```
┌─────────────────────────────────────────────────────┐
│  SIDEBAR (64px icon-only, expandable overlay)        │
│  MAIN CONTENT AREA (full width when sidebar closed)  │
└─────────────────────────────────────────────────────┘
```

#### Mobile (< 768px)
```
┌─────────────────────────────────────────────────────┐
│  TOP APP BAR (hamburger menu + title + actions)      │
│  MAIN CONTENT (full screen)                          │
│  BOTTOM NAVIGATION BAR (4-5 primary items)           │
└─────────────────────────────────────────────────────┘
```

### Reusable Component Specifications

#### Stat Card (like Reference 2's top row)
```
┌────────────────────────────┐
│  [Label text]              │
│  [Large Number]            │
│  [▲ X.XX%  Last 30 days]  │
└────────────────────────────┘
White background, 1px gray200 border, md border-radius, md padding
Number: 32px weight 700
Change: green if positive, red if negative
```

#### Status Badge (inline pill)
```
Approved  →  successLight bg + successColor text + ✓ icon
Pending   →  warningLight bg + warningColor text + ⏳ icon
Declined  →  dangerLight bg + dangerColor text + ✕ icon
Active    →  successLight bg + successColor text
Inactive  →  gray100 bg + gray400 text
```

#### Data Table
- White background, 1px gray200 border, radiusLg
- Header row: gray50 background, label typography, uppercase
- Row height: 56px (desktop), 64px (mobile friendly)
- Alternating row shading: none (use border separators only)
- Hover state: gray50 background
- Sortable columns show sort icon on hover
- Checkbox column on left for bulk actions
- Action column (kebab menu or action buttons) on right
- Pagination below: "Show [10▼] per page" + page numbers

#### Searchable Dropdown (Partner selector)
- Text input with search icon
- Dropdown list appears below with filtered results
- Each item shows: Member ID + Name + Fellowship
- "Create new partner" option appears at the bottom of results always
- Maximum 8 items visible before scroll

---

## 3. Tech Stack & Architecture Decisions

### Confirmed Stack

| Layer | Technology | Reason |
|---|---|---|
| **UI Framework** | Flutter (Dart) | Native performance, single codebase, pixel-perfect cross-platform |
| **State Management** | Riverpod (flutter_riverpod) | Best-in-class for Flutter, testable, async-first |
| **Navigation** | GoRouter | Declarative, deep-link friendly, role-based route guards |
| **Backend** | Firebase | Real-time, offline-first, mature Flutter SDK |
| **Database** | Firestore | Real-time sync, offline caching, NoSQL flexibility |
| **Auth** | Firebase Auth | Email/password + magic links + 2FA support |
| **Storage** | Firebase Storage | Church logos, exported files |
| **Functions** | Firebase Cloud Functions (Node.js 20) | Invite logic, email triggers, approval workflows, PDF generation |
| **Email** | Resend (via Cloud Functions) | Modern email API, reliable delivery |
| **PDF Generation** | pdf package (Flutter) + Cloud Functions | Client-side for simple exports, server-side for branded reports |
| **Notifications** | Firebase Cloud Messaging (FCM) | Industry-standard push notifications |
| **Analytics** | Firebase Analytics | Usage tracking, crash reporting |
| **Crash Reporting** | Firebase Crashlytics | Production error monitoring |
| **Design Tokens** | Custom ThemeData + Theme Extensions | Consistent design system |
| **HTTP Client** | Dio (for Cloud Function calls) | Interceptors, error handling |
| **Local Storage** | SharedPreferences + Hive | User preferences, offline queue |

### Package Dependencies (pubspec.yaml)
```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # Firebase
  firebase_core: ^3.x.x
  firebase_auth: ^5.x.x
  cloud_firestore: ^5.x.x
  firebase_storage: ^12.x.x
  firebase_messaging: ^15.x.x
  firebase_analytics: ^11.x.x
  firebase_crashlytics: ^4.x.x
  
  # State Management
  flutter_riverpod: ^2.x.x
  riverpod_annotation: ^2.x.x
  
  # Navigation
  go_router: ^14.x.x
  
  # UI & Design
  google_fonts: ^6.x.x
  flutter_animate: ^4.x.x
  shimmer: ^3.x.x
  
  # Data & Utilities
  intl: ^0.19.x
  uuid: ^4.x.x
  equatable: ^2.x.x
  freezed_annotation: ^2.x.x
  json_annotation: ^4.x.x
  
  # PDF & Export
  pdf: ^3.x.x
  printing: ^5.x.x
  share_plus: ^10.x.x
  path_provider: ^2.x.x
  
  # Local Storage
  shared_preferences: ^2.x.x
  hive_flutter: ^1.x.x
  
  # Network
  connectivity_plus: ^6.x.x
  dio: ^5.x.x
  
  # Misc
  image_picker: ^1.x.x
  cached_network_image: ^3.x.x
  fl_chart: ^0.69.x
  data_table_2: ^2.x.x
  dropdown_search: ^5.x.x

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.x.x
  freezed: ^2.x.x
  json_serializable: ^6.x.x
  riverpod_generator: ^2.x.x
  flutter_lints: ^4.x.x
```

---

## 4. Multi-Tenancy Architecture

### Concept

Every piece of data in the app belongs to a **church (tenant)**. Users belong to a church. Partners belong to a church. Entries belong to a church. This isolation is enforced at both the data model level and Firestore Security Rules level.

### Tenant Isolation Strategy

**Pattern:** Every top-level Firestore collection is either `churches` (which is the tenant root) or has `churchId` embedded in every document.

```
Firestore Root
├── churches/                          ← Top-level tenant collection
│   └── {churchId}/
│       ├── (church document)
│       ├── users/                     ← Subcollection: church members
│       ├── partners/                  ← Subcollection: giving partners
│       ├── entries/                   ← Subcollection: giving records
│       ├── partnership_arms/          ← Subcollection: arm categories
│       ├── partnership_periods/       ← Subcollection: time periods
│       ├── goals/                     ← Subcollection: period+arm goals
│       ├── invite_codes/              ← Subcollection: invitation tokens
│       └── activity_logs/            ← Subcollection: audit trail
└── user_church_index/                 ← Top-level index: uid → churchId
    └── {uid}/
        └── { churchId, role }
```

### The User-Church Index

When a user logs in, the app needs to find their church without scanning all churches. The `user_church_index` collection provides a fast lookup:

```
user_church_index/{uid} → { churchId: "abc123", role: "staff" }
```

This document is created by a Cloud Function when a user completes registration via an invite code.

---

## 5. Authentication & Invite System

### Overview Flow

```
Admin/Pastor generates invite → 
Resend email sends invite with unique code →
User receives email with link: https://thepillr2.web.app/join?code=XXXX →
User opens link, enters email + code on /join screen →
Code validated (Firebase Function) →
If valid: user shown registration form →
User fills: Full Name, Password, Phone →
Account created (Firebase Auth) →
user_church_index document created →
users/{uid} document created in church subcollection →
Invite code marked "accepted" →
User redirected to their role dashboard
```

### Invite Code Schema

```
churches/{churchId}/invite_codes/{codeId}
{
  code: "8-character alphanumeric uppercase",  // e.g. "A3BX9PLM"
  email: "recipient@email.com",
  role: "pastor" | "staff",                    // Admin invites are handled separately
  churchId: "abc123",
  createdBy: "uid-of-inviter",
  createdAt: Timestamp,
  expiresAt: Timestamp,                        // createdAt + 4 hours
  status: "pending" | "accepted" | "expired",
  acceptedBy: null | "uid",
  acceptedAt: null | Timestamp
}
```

### Invite Expiry

A Cloud Function runs on a schedule (every 30 minutes) to sweep invite codes and mark expired ones. Additionally, the validation function always checks `expiresAt` at the moment of validation.

### Sign-Up Screen Specifications

**Route:** `/join` or `/join?code=XXXX`

**Step 1 — Enter Code & Email:**
```
[Pillr Logo]
"You've been invited to join [Church Name]"
[Email input]
[Invite Code input — 8 character, auto-uppercase]
[Verify Invitation] button
```

**Step 2 — Complete Registration (shown after code verified):**
```
"Welcome! Complete your profile"
[Full Name input]
[Phone Number input (with country code selector)]
[Password input (with toggle show/hide)]
[Confirm Password input]
[Create Account] button
```

**Validations:**
- Email must match what the invite was sent to (checked server-side)
- Code must exist, be pending, and not expired
- Password: minimum 8 chars, at least 1 number, 1 uppercase

### Admin Invite Management Screen

Visible only to Admin and Pastor roles.

Shows a table:
| Email | Role | Sent By | Sent At | Expires At | Status | Actions |
|---|---|---|---|---|---|---|
| john@... | Staff | Pastor Mary | 2h ago | 2h left | Pending | Resend / Cancel |
| jane@... | Pastor | Admin | Yesterday | — | Accepted | — |

- **Send New Invite** button opens a modal: Email field + Role selector + Send button
- Pending invites show a countdown timer or "X hours left"
- Expired invites shown in muted style
- Resend button regenerates a new code and sends a new email (old code invalidated)

---

## 6. User Roles & Permissions

### Role Definitions

#### Admin (Tech Support)
- Created by the system or by another Admin
- One Admin per church (can be more for support purposes)
- Purpose: technical management, not financial data access
- **Cannot view:** entries, partner data, amounts, leaderboard, any financial information
- **Can do:** invite users (any role), view comprehensive activity logs, manage church settings (name, logo), view list of all users and their roles

#### Pastor
- Full access to church data
- Approves or declines all entries
- Manages all configuration
- **Can view:** everything — entries, partners, amounts, leaderboard, staff activity, approvals
- **Can do:** approve/decline/edit/update entries, create/manage goals, create/manage partnership arms and periods, invite users, make record entries, see who created each entry, view partner profile with full giving history

#### Church Staff
- Data entry role
- Limited view access
- **Can view:** only their own submitted entries and status
- **Can do:** create new entries (which go to pending), edit/update/delete their own entries (still requires Pastor re-approval), search and select partners, create new partners

### Permission Matrix (Comprehensive)

| Feature | Admin | Pastor | Staff |
|---|---|---|---|
| View own entries | — | ✓ | ✓ |
| View all entries | ✗ | ✓ | ✗ |
| Create entries | ✗ | ✓ | ✓ |
| Edit own entries | — | ✓ | ✓ (re-approval needed) |
| Edit any entry | ✗ | ✓ | ✗ |
| Delete own entries | — | ✓ | ✓ (if still pending) |
| Approve/Decline entries | ✗ | ✓ | ✗ |
| View leaderboard | ✗ | ✓ | ✗ |
| View partner list | ✗ | ✓ | ✓ (limited: search only) |
| View partner full profile | ✗ | ✓ | ✗ |
| Create partners | ✗ | ✓ | ✓ |
| Edit/Delete partners | ✗ | ✓ | ✗ |
| Manage partnership arms | ✗ | ✓ | ✗ |
| Manage partnership periods | ✗ | ✓ | ✗ |
| Manage goals | ✗ | ✓ | ✗ |
| Invite users | ✓ | ✓ | ✗ |
| View users list | ✓ | ✓ | ✗ |
| View activity logs (all) | ✓ | ✗ | ✗ |
| View approval logs | ✗ | ✓ | ✗ |
| Manage church settings | ✓ | ✗ | ✗ |
| Export logs (admin) | ✓ | ✗ | ✗ |
| Export records & leaderboard | ✗ | ✓ | ✗ |
| Export own entries | ✗ | ✓ | ✓ |

---

## 7. Data Models (Firestore)

### Church Document
```
churches/{churchId}
{
  id: string,
  name: string,                    // "Grace Community Church"
  slug: string,                    // "grace-community" — URL-friendly identifier
  logoUrl: string | null,          // Firebase Storage URL
  primaryColor: string | null,     // Hex color for branding e.g. "#1A56DB"
  address: string | null,
  contactEmail: string | null,
  contactPhone: string | null,
  timezone: string,                // e.g. "Africa/Accra"
  currency: string,                // e.g. "GHS"
  currencySymbol: string,          // e.g. "₵"
  createdAt: Timestamp,
  updatedAt: Timestamp,
  settings: {
    requireApproval: boolean,      // Always true for now
    allowStaffDeleteOwn: boolean,  // Can staff delete their own pending entries
    notifyPastorOnEntry: boolean,  // Push notify pastor on new entry
    notifyStaffOnApproval: boolean // Push notify staff on approval/decline
  }
}
```

### User Document
```
churches/{churchId}/users/{uid}
{
  uid: string,                     // Firebase Auth UID
  churchId: string,
  role: "admin" | "pastor" | "staff",
  fullName: string,
  email: string,
  phone: string | null,
  avatarUrl: string | null,
  isActive: boolean,
  fcmToken: string | null,         // Firebase Cloud Messaging token for push notifications
  inviteCodeId: string | null,     // Reference to the invite code used
  createdAt: Timestamp,
  updatedAt: Timestamp,
  lastLoginAt: Timestamp | null
}
```

### Partner Document
```
churches/{churchId}/partners/{partnerId}
{
  id: string,
  churchId: string,
  memberId: string,                // Church-assigned member ID e.g. "MBR0042"
  fullName: string,
  fellowship: string,              // Which fellowship/cell group they belong to
  email: string | null,
  phone: string | null,
  isActive: boolean,
  totalApprovedAmount: number,     // Denormalized: sum of all approved entries (GHS)
  entryCount: number,              // Denormalized: total approved entry count
  createdBy: string,               // uid of user who created this partner
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### Entry Document
```
churches/{churchId}/entries/{entryId}
{
  id: string,
  churchId: string,
  partnerId: string,               // Reference to partner document
  partnerSnapshot: {               // Snapshot at time of entry (for historical accuracy)
    memberId: string,
    fullName: string,
    fellowship: string,
    email: string | null,
    phone: string | null
  },
  partnershipArmId: string,        // Reference to arm document
  armSnapshot: {                   // Snapshot at time of entry
    name: string
  },
  partnershipPeriodId: string,     // Reference to period document
  periodSnapshot: {                // Snapshot at time of entry
    name: string,
    startDate: Timestamp,
    endDate: Timestamp
  },
  amountCedis: number,             // Amount in Ghana Cedis (e.g. 500.00)
  dateGiven: Timestamp,            // The actual date the member gave (not recording date)
  notes: string | null,            // Optional notes by staff
  status: "pending" | "approved" | "declined",
  createdBy: string,               // uid of staff who entered this record
  createdBySnapshot: {
    fullName: string,
    role: string
  },
  createdAt: Timestamp,
  updatedAt: Timestamp,
  reviewedBy: string | null,       // uid of pastor who reviewed
  reviewedBySnapshot: {
    fullName: string
  } | null,
  reviewedAt: Timestamp | null,
  declineReason: string | null,    // If declined, pastor gives reason
  editHistory: [                   // Array of edit events
    {
      editedBy: string,
      editedAt: Timestamp,
      previousValues: { ... },     // Snapshot of fields before edit
      changeDescription: string
    }
  ]
}
```

### Partnership Arm Document
```
churches/{churchId}/partnership_arms/{armId}
{
  id: string,
  churchId: string,
  name: string,                    // "Venue", "Rhapsody", etc.
  description: string | null,
  isActive: boolean,               // Toggle active/inactive
  colorHex: string | null,         // Optional color for visual identification
  sortOrder: number,               // For ordering in lists
  createdBy: string,
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### Partnership Period Document
```
churches/{churchId}/partnership_periods/{periodId}
{
  id: string,
  churchId: string,
  name: string,                    // "Q1 2025", "Annual Partnership 2025"
  description: string | null,
  startDate: Timestamp,
  endDate: Timestamp,
  isActive: boolean,               // ONLY ONE CAN BE TRUE at a time (enforced by Cloud Function)
  totalApprovedAmount: number,     // Denormalized sum of approved entries in this period
  entryCount: number,              // Denormalized count
  createdBy: string,
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### Goal Document
```
churches/{churchId}/goals/{goalId}
{
  id: string,
  churchId: string,
  partnershipPeriodId: string,
  partnershipArmId: string,
  targetAmountCedis: number,
  currentAmountCedis: number,      // Denormalized: updated on each entry approval
  createdBy: string,
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### Invite Code Document
```
churches/{churchId}/invite_codes/{codeId}
{
  id: string,
  churchId: string,
  code: string,                    // 8-char alphanumeric e.g. "A3BX9PLM"
  email: string,                   // Who it was sent to
  role: "admin" | "pastor" | "staff",
  createdBy: string,               // uid of inviter
  createdBySnapshot: {
    fullName: string,
    role: string
  },
  createdAt: Timestamp,
  expiresAt: Timestamp,            // createdAt + 4 hours
  status: "pending" | "accepted" | "expired",
  acceptedBy: string | null,
  acceptedAt: Timestamp | null
}
```

### Activity Log Document
```
churches/{churchId}/activity_logs/{logId}
{
  id: string,
  churchId: string,
  actorUid: string,
  actorSnapshot: {
    fullName: string,
    role: string,
    email: string
  },
  action: string,                  // Enum: see Action Types below
  entityType: "entry" | "partner" | "user" | "arm" | "period" | "goal" | "invite" | "auth",
  entityId: string | null,         // ID of the affected document
  entitySnapshot: { ... } | null,  // Snapshot of entity at time of action
  metadata: { ... } | null,        // Additional context (e.g. declineReason)
  ipAddress: string | null,
  userAgent: string | null,
  createdAt: Timestamp
}
```

**Action Types:**
```
auth.login, auth.logout, auth.passwordReset
entry.create, entry.update, entry.delete, entry.approve, entry.decline
partner.create, partner.update, partner.delete
user.invite, user.register, user.deactivate, user.roleChange
arm.create, arm.update, arm.delete, arm.toggle
period.create, period.update, period.delete, period.activate, period.deactivate
goal.create, goal.update, goal.delete
export.pdf, export.csv
```

---

## 8. Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // ─── Helper Functions ────────────────────────────────────────────────
    
    function isAuthenticated() {
      return request.auth != null;
    }
    
    function getUserData() {
      return get(/databases/$(database)/documents/user_church_index/$(request.auth.uid)).data;
    }
    
    function getUserChurchId() {
      return getUserData().churchId;
    }
    
    function getUserRole() {
      return getUserData().role;
    }
    
    function isRole(role) {
      return isAuthenticated() && getUserRole() == role;
    }
    
    function isAdmin() { return isRole('admin'); }
    function isPastor() { return isRole('pastor'); }
    function isStaff() { return isRole('staff'); }
    function isPastorOrAdmin() { return isAdmin() || isPastor(); }
    function isPastorOrStaff() { return isPastor() || isStaff(); }
    
    function belongsToChurch(churchId) {
      return isAuthenticated() && getUserChurchId() == churchId;
    }
    
    function isOwnEntry(entry) {
      return entry.createdBy == request.auth.uid;
    }
    
    // ─── User Church Index ───────────────────────────────────────────────
    
    match /user_church_index/{uid} {
      // Only Cloud Functions write this. Users can read their own.
      allow read: if request.auth.uid == uid;
      allow write: if false; // Cloud Functions only
    }
    
    // ─── Church Document ─────────────────────────────────────────────────
    
    match /churches/{churchId} {
      allow read: if belongsToChurch(churchId);
      allow write: if belongsToChurch(churchId) && isAdmin();
      
      // ─── Users ──────────────────────────────────────────────────────
      match /users/{uid} {
        allow read: if belongsToChurch(churchId) && isPastorOrAdmin();
        allow read: if request.auth.uid == uid; // Own profile always
        allow create: if false; // Cloud Functions only (registration)
        allow update: if belongsToChurch(churchId) && (isAdmin() || request.auth.uid == uid);
        allow delete: if belongsToChurch(churchId) && isAdmin();
      }
      
      // ─── Partners ────────────────────────────────────────────────────
      match /partners/{partnerId} {
        allow read: if belongsToChurch(churchId) && (isPastor() || isStaff());
        allow create: if belongsToChurch(churchId) && (isPastor() || isStaff());
        allow update: if belongsToChurch(churchId) && isPastor();
        allow delete: if belongsToChurch(churchId) && isPastor();
      }
      
      // ─── Entries ─────────────────────────────────────────────────────
      match /entries/{entryId} {
        // Pastor sees all, staff sees own only
        allow read: if belongsToChurch(churchId) && isPastor();
        allow read: if belongsToChurch(churchId) && isStaff() && isOwnEntry(resource.data);
        
        // Create: Pastor and Staff
        allow create: if belongsToChurch(churchId) && isPastorOrStaff()
                      && request.resource.data.status == 'pending';
        
        // Update: Pastor can update anything, Staff can update own pending entries
        allow update: if belongsToChurch(churchId) && isPastor();
        allow update: if belongsToChurch(churchId) && isStaff()
                      && isOwnEntry(resource.data)
                      && resource.data.status == 'pending'
                      && request.resource.data.status == 'pending'; // Can't self-approve
        
        // Delete: Pastor always, Staff only own pending entries
        allow delete: if belongsToChurch(churchId) && isPastor();
        allow delete: if belongsToChurch(churchId) && isStaff()
                      && isOwnEntry(resource.data)
                      && resource.data.status == 'pending';
      }
      
      // ─── Partnership Arms ────────────────────────────────────────────
      match /partnership_arms/{armId} {
        allow read: if belongsToChurch(churchId);
        allow write: if belongsToChurch(churchId) && isPastor();
      }
      
      // ─── Partnership Periods ─────────────────────────────────────────
      match /partnership_periods/{periodId} {
        allow read: if belongsToChurch(churchId);
        allow write: if belongsToChurch(churchId) && isPastor();
      }
      
      // ─── Goals ──────────────────────────────────────────────────────
      match /goals/{goalId} {
        allow read: if belongsToChurch(churchId) && isPastor();
        allow write: if belongsToChurch(churchId) && isPastor();
      }
      
      // ─── Invite Codes ────────────────────────────────────────────────
      match /invite_codes/{codeId} {
        allow read: if belongsToChurch(churchId) && isPastorOrAdmin();
        allow create: if belongsToChurch(churchId) && isPastorOrAdmin();
        allow update: if false; // Cloud Functions only
        allow delete: if belongsToChurch(churchId) && isPastorOrAdmin();
      }
      
      // ─── Activity Logs ───────────────────────────────────────────────
      match /activity_logs/{logId} {
        allow read: if belongsToChurch(churchId) && isAdmin();
        allow read: if belongsToChurch(churchId) && isPastor()
                    && resource.data.entityType in ['entry', 'partner', 'user', 'invite'];
        allow create: if belongsToChurch(churchId); // Any authenticated user can create logs
        allow update: if false; // Logs are immutable
        allow delete: if false; // Logs are immutable
      }
    }
  }
}
```

---

## 9. Feature Specifications

### 9.1 Entry Recording

**Entry Form Fields:**

| Field | Type | Required | Behavior |
|---|---|---|---|
| Partnership Arm | Dropdown | Yes | Shows active arms only, preselects if only one active |
| Partnership Period | Dropdown | Yes | Shows active period (auto-selected since only one active) |
| Amount (Cedis) | Number input | Yes | Numeric keyboard, 2 decimal places, ₵ symbol prefix |
| Date Given | Date picker | Yes | Defaults to today, cannot be future date |
| Partner | Searchable dropdown | Yes | See specification below |

**Partner Searchable Dropdown Behavior:**
1. Staff taps/clicks the partner field
2. A search input appears with dropdown below
3. As user types, Firestore query filters by: fullName (contains), memberId (starts with), phone (starts with), fellowship (starts with)
4. Results show: `[MBR0042] John Mensah — Restoration Fellowship`
5. Selecting a partner populates the bio data preview below the field
6. If no results found, show "No partner found. [+ Create New Partner]"
7. "Create New Partner" opens a bottom sheet / modal with partner creation form

**Partner Bio Preview (shown after selection):**
```
┌─────────────────────────────────────┐
│  👤 John Mensah                     │
│  ID: MBR0042  |  Restoration Fel.  │
│  📱 +233 24 000 0000               │
│  ✉️  john@email.com                │
└─────────────────────────────────────┘
```

**Entry Submission Flow:**
1. Staff fills form → taps "Submit for Approval"
2. Entry created with status: `pending`
3. Activity log entry created
4. Push notification sent to Pastor (via FCM)
5. Staff sees entry in their "My Entries" list with "Pending" badge
6. Pastor receives notification: "New entry submitted by [Staff Name] for [Partner Name] — ₵[Amount]"

### 9.2 Entry Approval (Pastor)

**Pending Entries Queue:**
- Pastor sees a dedicated "Pending Approvals" section/tab
- Each pending entry shows:
  - Partner name + member ID
  - Amount in Cedis (large, prominent)
  - Partnership Arm
  - Partnership Period
  - Date Given
  - Submitted by [Staff Name] at [Time]
- Two action buttons: **Approve** (green) | **Decline** (red)
- Decline opens a small modal asking for a reason (required text input)

**After Approval:**
1. Entry status → `approved`
2. Partner's `totalApprovedAmount` incremented
3. Period's `totalApprovedAmount` incremented
4. Goal's `currentAmountCedis` incremented (if goal exists for this arm+period)
5. Activity log written
6. Staff notified: "Your entry for [Partner] (₵[Amount]) was approved by Pastor [Name]"

**After Decline:**
1. Entry status → `declined`
2. Decline reason stored on entry
3. Staff notified: "Your entry for [Partner] (₵[Amount]) was declined. Reason: [reason]"

**Re-submission Flow:**
- Staff can edit a declined entry (all fields editable)
- After editing, entry status resets to `pending`
- Pastor re-reviews

### 9.3 Partnership Arms Management (Pastor)

**Arms List Screen:**
- Table/list of all arms
- Each row: Name | Description | Status (Active/Inactive toggle) | # Entries | Actions
- Actions: Edit (pencil) | Delete (trash, with confirmation if no entries)

**Create/Edit Arm:**
- Name (required, unique within church)
- Description (optional)
- Color (optional color picker for visual identification)
- Active toggle

**Delete Rules:**
- Arm can only be deleted if it has zero entries
- If entries exist, show error: "This arm has [N] entries. Archive it instead by toggling inactive."

**Toggle Active:**
- Any arm can be toggled active/inactive at any time
- Inactive arms do not appear in the entry form dropdown
- Existing entries with inactive arms are unaffected

### 9.4 Partnership Periods Management (Pastor)

**Periods List Screen:**
- Each period: Name | Date Range | Status | Total Collected | # Entries | Actions

**Create Period:**
- Name (required)
- Description (optional)
- Start Date (required)
- End Date (required)
- Active toggle

**CRITICAL RULE — Only one active period at a time:**
- When activating a period, a Cloud Function (triggered by Firestore write) deactivates all other periods
- UI shows a confirmation: "Activating this period will deactivate [Current Active Period Name]. Continue?"
- This is enforced server-side; the UI confirmation is for UX only

### 9.5 Leaderboard (Pastor & Staff — NO, only Pastor)

> **Clarification from spec:** Leaderboard is visible to Pastor and "financial head (staff)" — interpret as: all Staff can see the leaderboard. Adjust if needed.

> **Final decision from spec review:** Leaderboard visible to **Pastor only** and explicitly authorized staff (future role enhancement). For now: **Pastor only**.

**Leaderboard Display:**
```
┌─────────────────────────────────────────────────────┐
│  LEADERBOARD  |  [Period Selector ▼]  [Arm Filter ▼] │
├─────────────────────────────────────────────────────┤
│  🥇  #1  John Mensah          ₵ 12,500.00           │
│           MBR0042 | Restoration Fellowship           │
│  🥈  #2  Sarah Asante         ₵  9,800.00           │
│  🥉  #3  Emmanuel Boateng     ₵  7,200.00           │
│      #4  ...                                        │
└─────────────────────────────────────────────────────┘
```

- Filterable by: Partnership Period, Partnership Arm
- Default shows current active period, all arms
- Shows rank number, partner name, total approved amount
- Top 3 get medal icons (🥇🥈🥉)
- Tapping a partner opens their full profile (Pastor only)

### 9.6 Partner Profile (Pastor)

Full profile view when Pastor taps a partner:

```
┌─────────────────────────────────────────────────────┐
│  [Back]  Partner Profile                             │
│  ─────────────────────────────────────────────────  │
│  👤  John Mensah                                     │
│  Member ID: MBR0042                                  │
│  Fellowship: Restoration Fellowship                  │
│  📱 +233 24 000 0000  |  ✉️  john@gmail.com         │
│  ─────────────────────────────────────────────────  │
│  Total Approved  |  Entry Count  |  Since           │
│  ₵ 32,500.00    |  14 entries   |  Jan 2024         │
│  ─────────────────────────────────────────────────  │
│  [Giving History]                                    │
│  Period         | Arm     | Amount  | Date  | Status │
│  Annual 2025    | Venue   | ₵2,000  | Mar 5 | ✓      │
│  Annual 2025    | Rhapsody| ₵1,500  | Feb 1 | ✓      │
│  Q4 2024        | Venue   | ₵3,000  | Dec 3 | ✓      │
└─────────────────────────────────────────────────────┘
```

### 9.7 Goal Tracking

**Create Goal (Pastor):**
- Select Partnership Period
- Select Partnership Arm
- Enter target amount in Cedis
- One goal per period+arm combination (enforced)

**Goal Display (Pastor Dashboard):**
```
Partnership Goals — Annual 2025
┌────────────────────────────────────────────────┐
│  Venue Arm                                     │
│  ₵ 24,500 / ₵ 50,000                         │
│  ████████████░░░░░░░░  49%                    │
│                                                │
│  Rhapsody Arm                                  │
│  ₵ 8,200 / ₵ 20,000                          │
│  ████░░░░░░░░░░░░░░░░  41%                    │
└────────────────────────────────────────────────┘
```

### 9.8 Offline Support

Firestore Flutter SDK handles offline caching automatically. Additional considerations:

1. **Connectivity Banner:** When offline, show a subtle yellow banner at the top: "You're offline. Changes will sync when connected."
2. **Pending Sync Queue:** When an entry is submitted offline, it's queued in Firestore's local cache. When connectivity restores, it syncs automatically.
3. **Conflict Resolution:** Firestore handles last-write-wins; document this for staff training.
4. **No Offline Photo Uploads:** Partner avatars cannot be uploaded offline.

---

## 10. UI/UX Specifications

### 10.1 App Shell

#### Sidebar Navigation (Desktop/Tablet)

```
┌────────────────────────┐
│  [Logo]  Pillr         │
│  [Church Name]         │
│  ─────────────────     │
│  🏠 Dashboard          │
│  📋 Entries            │  (label changes by role)
│  👥 Partners           │  (Pastor only)
│  🏆 Leaderboard        │  (Pastor only)
│  📊 Goals              │  (Pastor only)
│  ─────────────────     │
│  CONFIGURATION         │
│  💪 Partnership Arms   │  (Pastor only)
│  📅 Periods            │  (Pastor only)
│  ─────────────────     │
│  ADMIN                 │
│  👤 Users              │  (Admin + Pastor)
│  📨 Invitations        │  (Admin + Pastor)
│  📋 Activity Logs      │  (Admin only)
│  ─────────────────     │
│  ⚙️  Settings          │
│  ─────────────────     │
│  [Avatar] [Name]       │
│  [Role badge]          │
│  [Logout]              │
└────────────────────────┘
```

Navigation items appear/disappear based on user role. No "coming soon" items — if not applicable, simply not shown.

#### Bottom Navigation (Mobile)

**Pastor:**
- Dashboard | Entries | Partners | Leaderboard | More (...)

**Staff:**
- Dashboard | My Entries | New Entry | Settings

**Admin:**
- Dashboard | Users | Invitations | Logs | Settings

#### Top Bar (All Screen Sizes)
- Left: Hamburger menu (mobile) or church name (desktop)
- Center: Page title
- Right: Notification bell (with unread count badge) + User avatar

### 10.2 Dashboard Screens

#### Pastor Dashboard

Row 1 — Stat Cards (4 columns, responsive to 2x2 on mobile):
```
[Total Collected (Active Period)]  [Pending Approvals]
[Total Partners]                   [Goal Progress %]
```

Row 2 — Quick Actions:
```
[Approve Pending (N)] button    [New Entry] button
```

Row 3 — Recent Activity:
Last 10 activity items in a timeline list

Row 4 — Goal Progress Bars:
All goals for active period with progress bars

Row 5 — Leaderboard Preview:
Top 5 partners for current period

#### Staff Dashboard

Row 1 — Stat Cards (2 columns):
```
[My Entries This Period]    [My Approved Total]
```

Row 2 — Quick Action:
```
[+ New Entry] large button
```

Row 3 — My Recent Entries:
Last 10 entries submitted by this staff member with status badges

#### Admin Dashboard

Row 1 — Stat Cards:
```
[Total Users]    [Active Invites]    [System Events Today]
```

Row 2 — Recent Activity Log:
Last 20 activity events in a clean timeline

Row 3 — Pending Invitations:
List of pending invites with time-remaining countdown

### 10.3 Entry Form Screen

**Mobile Layout:**
- Full screen form
- Sticky bottom submit button
- Progress indicator (optional: step 1/2 if long)

**Desktop Layout:**
- Right panel slide-in from right (drawer pattern)
- OR centered modal (max-width 560px)
- Submit button inside the panel/modal

**Form Field Order:**
1. Partnership Period (auto-filled with active, read-only if only one option)
2. Partnership Arm (dropdown, required)
3. Partner (searchable dropdown, required)
4. [Partner bio preview card appears here after selection]
5. Amount (₵) — prominent number input
6. Date Given — date picker (defaults to today)
7. Notes — optional text area
8. Submit button: "Submit for Approval" (Staff) or "Add Entry" (Pastor — auto-approved)

> **Note:** When Pastor adds an entry directly, it bypasses the approval flow and is immediately `approved`. This should be communicated clearly in the UI ("This entry will be immediately approved").

### 10.4 Entries List Screen

**Pastor View:**
- Tabs: All | Pending | Approved | Declined
- Filter bar: Period | Arm | Date Range | Search (partner name)
- Sortable table columns: Date | Partner | Arm | Amount | Status | Submitted By

**Staff View:**
- No tabs (only their own entries)
- Same filter options
- "Submitted by" column hidden (it's always them)

### 10.5 Animations & Micro-interactions

- Use `flutter_animate` package for all animations
- List items fade in with a 50ms stagger between items
- Stat cards animate numbers counting up when the dashboard first loads
- Status badge color transitions are animated (300ms ease)
- Sidebar collapses/expands with 200ms slide animation
- Bottom sheet slides up with spring animation
- Success state after form submission: green checkmark animation, then navigate away
- Pull-to-refresh on all lists with custom refresh indicator
- Shimmer loading state on all data-fetching screens

### 10.6 Error States

Every screen must handle:
- **Loading:** Shimmer skeleton matching the expected layout
- **Empty:** Illustration + helpful message + action button (e.g. "No entries yet. [+ Add First Entry]")
- **Error:** Error message + retry button
- **Offline:** Offline banner + cached data shown where available
- **Permission Denied:** "You don't have permission to view this" message

---

## 11. Export System

### PDF Export Specifications

**All exports include:**
- Church logo (top left) and church name
- Export date and time
- Name of user who exported
- "The Pillr" watermark in footer

#### Pastor — Giving Records Export
**Contents:** Filterable table of entries with columns:
Date Given | Partner Name | Member ID | Fellowship | Arm | Period | Amount | Status | Submitted By | Approved By

**Filename format:** `pillr_records_[period-name]_[date].pdf`

#### Pastor — Approval Log Export
**Contents:** List of all approval/decline events:
Date | Entry (Partner + Amount) | Action | By (Pastor) | Reason (if declined)

#### Pastor — Leaderboard Export
**Contents:** Ranked leaderboard for selected period:
Rank | Partner Name | Member ID | Fellowship | Total Amount | Entry Count

**Includes:** Period name, generation timestamp, church branding

#### Staff — My Entries Export
**Contents:** Staff member's own entries with all fields

#### Admin — Activity Logs Export (CSV only)
**Contents:** Raw activity log with all fields in CSV format

### CSV Export Format

All CSVs use:
- UTF-8 encoding
- Comma delimiter
- Double-quote string encapsulation
- ISO 8601 dates (YYYY-MM-DD HH:MM:SS)
- Header row first
- Cedi amounts as plain numbers (no ₵ symbol in CSV)

### Export Implementation

```dart
// Use the `pdf` Flutter package for PDF generation
// Use `share_plus` to share the file
// Use `path_provider` to get the temp directory for saving

Future<void> exportToPdf(ExportConfig config) async {
  final pdf = pw.Document();
  // Build pages
  pdf.addPage(pw.MultiPage(
    header: (context) => buildHeader(context, church),
    footer: (context) => buildFooter(context),
    build: (context) => [buildTable(context, data)],
  ));
  final bytes = await pdf.save();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${filename}.pdf');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles([XFile(file.path)]);
}
```

---

## 12. Notification System

### Push Notification Events

| Event | Recipient | Message |
|---|---|---|
| New entry submitted | Pastor | "[Staff Name] added an entry: [Partner] — ₵[Amount]" |
| Entry approved | Staff who submitted | "✓ Your entry for [Partner] (₵[Amount]) was approved" |
| Entry declined | Staff who submitted | "✗ Your entry for [Partner] (₵[Amount]) was declined: [reason]" |
| Entry edited (after approval) | Pastor | "[Staff Name] edited a previously approved entry for [Partner]" |
| Invite accepted | Admin/Pastor who sent it | "[Name] accepted your invitation and joined as [Role]" |
| Goal reached (100%) | Pastor | "🎉 Goal reached! [Arm] for [Period] hit its ₵[Target] target!" |

### FCM Token Management

```dart
// On login, always update FCM token in user document
final token = await FirebaseMessaging.instance.getToken();
await FirebaseFirestore.instance
  .doc('churches/$churchId/users/$uid')
  .update({'fcmToken': token});

// Listen for token refresh
FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
  // Update in Firestore
});
```

### Notification Channels (Android)

```dart
const AndroidNotificationChannel entriesChannel = AndroidNotificationChannel(
  'entries_channel',
  'Entry Notifications',
  description: 'Notifications about partnership entries',
  importance: Importance.high,
);

const AndroidNotificationChannel approvalsChannel = AndroidNotificationChannel(
  'approvals_channel',
  'Approval Notifications',
  description: 'Notifications about entry approvals and declines',
  importance: Importance.high,
);
```

---

## 13. Phase 1 — Foundation

**Duration estimate:** 2-3 weeks  
**Goal:** Working app shell, authentication, invite system, basic navigation

### Phase 1 Checklist

#### 1.1 Flutter Project Setup
- [ ] Create Flutter project: `flutter create the_pillr`
- [ ] Configure `pubspec.yaml` with all dependencies listed in Section 3
- [ ] Set up folder structure as described in Section 17
- [ ] Configure app icons and splash screens for iOS, Android, Web
- [ ] Configure app name: "Pillr" (display name)
- [ ] Set up flavor/environment configs: development, staging, production

#### 1.2 Firebase Setup
- [x] Create Firebase project: `thepillr2` ← ALREADY CREATED
- [ ] Enable Authentication (Email/Password provider)
- [ ] Enable Firestore Database
- [ ] Enable Firebase Storage
- [ ] Enable Firebase Cloud Messaging
- [ ] Enable Firebase Analytics
- [ ] Enable Firebase Crashlytics
- [ ] Configure `google-services.json` (Android)
- [ ] Configure `GoogleService-Info.plist` (iOS)
- [ ] Configure Firebase for Flutter Web
- [ ] Initialize Firebase in `main.dart`

#### 1.3 Design System Implementation
- [ ] Create `app_colors.dart` with full color palette from Section 2
- [ ] Create `app_typography.dart` with Inter font + text styles
- [ ] Create `app_spacing.dart` with spacing constants
- [ ] Create `app_theme.dart` with full `ThemeData` configuration
- [ ] Create reusable widgets:
  - `PillrButton` (primary, secondary, danger, ghost variants)
  - `PillrTextField` (with label, hint, error state)
  - `PillrCard` (white card with shadow)
  - `PillrBadge` (status pill — approved/pending/declined/active/inactive)
  - `PillrStatCard` (stat card as in Reference 2)
  - `PillrDataTable` (sortable, paginated table)
  - `PillrLoadingShimmer` (skeleton loader)
  - `PillrEmptyState` (illustration + message + action)
  - `PillrErrorState` (error + retry)

#### 1.4 Navigation Setup
- [ ] Configure GoRouter with all routes
- [ ] Implement route guards (redirect to login if not authenticated, redirect based on role)
- [ ] Implement adaptive navigation (sidebar on desktop, bottom nav on mobile)
- [ ] Create `AppShell` widget that wraps all authenticated screens

**Routes:**
```dart
/                          → redirect to /dashboard or /login
/login                     → LoginScreen
/join                      → JoinScreen (invite registration)
/join?code=XXXX            → JoinScreen with pre-filled code

// Authenticated routes (inside AppShell):
/dashboard                 → Role-appropriate DashboardScreen
/entries                   → EntriesListScreen
/entries/new               → NewEntryScreen
/entries/:id               → EntryDetailScreen
/partners                  → PartnersListScreen (Pastor only)
/partners/:id              → PartnerProfileScreen (Pastor only)
/leaderboard               → LeaderboardScreen (Pastor only)
/goals                     → GoalsScreen (Pastor only)
/arms                      → ArmsScreen (Pastor only)
/periods                   → PeriodsScreen (Pastor only)
/users                     → UsersScreen (Pastor + Admin)
/invitations               → InvitationsScreen (Pastor + Admin)
/logs                      → ActivityLogsScreen (Admin only)
/settings                  → SettingsScreen
```

#### 1.5 Authentication Implementation
- [ ] Login screen (email + password, forgot password link)
- [ ] Logout functionality
- [ ] Auth state persistence (stay logged in)
- [ ] Firebase Auth state stream in Riverpod
- [ ] Error handling for wrong password, user not found, network error
- [ ] Password reset email flow

#### 1.6 Invite System Implementation
- [ ] Cloud Function: `generateInviteCode` (POST)
  - Accepts: `{ email, role, churchId }`
  - Validates: caller is Admin or Pastor of that church
  - Creates invite_codes document with 4-hour expiry
  - Sends email via Resend API
  - Returns: `{ success, codeId }`
- [ ] Cloud Function: `validateInviteCode` (POST)
  - Accepts: `{ code, email }`
  - Validates: code exists, matches email, not expired, pending
  - Returns: `{ valid, churchName, role, churchId, codeId }`
- [ ] Cloud Function: `completeRegistration` (POST — callable, requires firebase auth token)
  - Accepts: `{ fullName, phone, codeId }`
  - Creates: `user_church_index/{uid}`, `churches/{churchId}/users/{uid}`
  - Updates: invite_code status to `accepted`
  - Returns: `{ success }`
- [ ] Join screen UI (two-step as described in Section 5)
- [ ] Invitation management screen (table of all invite codes)
- [ ] Send invite modal/dialog

#### 1.7 Multi-Tenancy Foundation
- [ ] `user_church_index` lookup on login
- [ ] Store `churchId` in app state (Riverpod provider)
- [ ] All Firestore queries scoped to `churches/{churchId}/...`
- [ ] Firestore Security Rules (from Section 8) deployed

---

## 14. Phase 2 — Core Features

**Duration estimate:** 3-4 weeks  
**Goal:** Full entry recording, partner management, arms/periods configuration, approval workflow

### Phase 2 Checklist

#### 2.1 Partnership Arms
- [ ] Arms list screen with table
- [ ] Create arm modal/form
- [ ] Edit arm inline or in modal
- [ ] Delete arm (with validation)
- [ ] Toggle active/inactive with animated switch
- [ ] Firestore CRUD operations
- [ ] Activity logging on all arm actions

#### 2.2 Partnership Periods
- [ ] Periods list screen
- [ ] Create period form with date range picker
- [ ] Edit period form
- [ ] Delete period (with validation — no entries)
- [ ] **Single active period enforcement:**
  - UI shows confirmation dialog
  - Cloud Function: `activatePeriod` — deactivates all others, activates requested
- [ ] Activity logging

#### 2.3 Partner Management
- [ ] Partners list screen (Pastor): searchable, filterable table
- [ ] Partner creation form (Staff and Pastor):
  - Member ID (required, unique within church)
  - Full Name (required)
  - Fellowship (required)
  - Email (optional)
  - Phone (optional)
- [ ] Partner edit form (Pastor only)
- [ ] Partner soft-delete / deactivate (Pastor only)
- [ ] Searchable partner dropdown component (for entry form)
  - Real-time Firestore search as user types
  - Show: MemberID + Name + Fellowship
  - "Create New Partner" option at bottom
- [ ] Activity logging

#### 2.4 Entry Recording
- [ ] Entry form screen (full spec in Section 9.1)
- [ ] Searchable partner dropdown integrated
- [ ] Create new partner inline (bottom sheet from within entry form)
- [ ] Entry submission → status: pending
- [ ] Push notification to Pastor on new entry
- [ ] Activity log entry
- [ ] Staff "My Entries" list screen with status badges
- [ ] Entry detail view

#### 2.5 Approval Workflow
- [ ] Pending approvals queue screen (Pastor)
- [ ] Entry review card UI (Partner info + Amount + Arm + Period + Submitted by)
- [ ] Approve action → update status, update denormalized counters
- [ ] Decline action → modal with required reason input → update status
- [ ] Cloud Function: `onEntryStatusChange` — triggered by Firestore update
  - Sends push notification to staff
  - Updates `partner.totalApprovedAmount`, `period.totalApprovedAmount`, `goal.currentAmountCedis`
- [ ] Activity logging on all approval actions
- [ ] Staff notification on approval/decline

#### 2.6 Entry Edit/Re-submission
- [ ] Staff can edit their own pending or declined entries
- [ ] After edit, status resets to pending (requires re-approval)
- [ ] Edit history appended to entry document
- [ ] Pastor can edit any entry (status stays as-is unless Pastor changes it)
- [ ] Pastor edit → activity log with before/after values

#### 2.7 Real-time Updates
- [ ] Use Firestore `snapshots()` streams everywhere (not one-time `.get()`)
- [ ] Pending approvals count in sidebar badge updates live
- [ ] Stat cards on dashboard update live
- [ ] New entries appear in lists without manual refresh

---

## 15. Phase 3 — Roles, Dashboards & Leaderboard

**Duration estimate:** 2-3 weeks  
**Goal:** Role-specific dashboards, leaderboard, goal tracking, complete permission enforcement

### Phase 3 Checklist

#### 3.1 Pastor Dashboard
- [ ] 4-column stat cards (Total Collected, Pending Approvals, Total Partners, Goal Progress %)
- [ ] Quick action buttons (Approve Pending, New Entry)
- [ ] Recent activity timeline (last 10 events)
- [ ] Goal progress bars for current period (all arms)
- [ ] Leaderboard preview (top 5)
- [ ] Animated number counter on stat cards

#### 3.2 Staff Dashboard
- [ ] 2-column stat cards (My Entries, My Approved Total)
- [ ] Large "New Entry" CTA button
- [ ] My Recent Entries list (last 10, with status badges)
- [ ] Notification for declined entries prominently displayed

#### 3.3 Admin Dashboard
- [ ] User count, active invites, system events stats
- [ ] Recent activity log timeline
- [ ] Pending invitations list with countdown timers
- [ ] Church settings quick access

#### 3.4 Leaderboard
- [ ] Leaderboard screen (Pastor only)
- [ ] Period selector dropdown
- [ ] Arm filter dropdown (or "All Arms")
- [ ] Ranked list with medal icons for top 3
- [ ] Partner tap → Partner Profile screen
- [ ] Real-time updates via Firestore stream

#### 3.5 Goal Management
- [ ] Goals list screen (Pastor)
- [ ] Create goal form (Period + Arm + Target Amount)
- [ ] One goal per Period+Arm combination validation
- [ ] Goal progress display with progress bar
- [ ] Edit/delete goal
- [ ] Cloud Function updates `goal.currentAmountCedis` on entry approval

#### 3.6 Partner Profile (Pastor)
- [ ] Full profile screen
- [ ] Bio data section
- [ ] Aggregate stats (total, count, since date)
- [ ] Full giving history table (all entries, all periods)
- [ ] Filter history by period and arm
- [ ] "Recurring Partner" badge if gave in 3+ consecutive periods
- [ ] Edit partner button (leads to edit form)

#### 3.7 Activity Logs (Admin)
- [ ] Comprehensive logs screen
- [ ] Filterable by: date range, action type, actor, entity type
- [ ] Searchable by actor name or entity ID
- [ ] Paginated (20 per page)
- [ ] Each log entry shows:
  - Timestamp (relative + absolute on hover)
  - Actor name + role + avatar
  - Action description (human-readable)
  - Entity affected (with link to entity if accessible)
- [ ] Export to CSV button

#### 3.8 Complete Permission Enforcement
- [ ] Route guards: redirect unauthorized users
- [ ] UI elements hidden/shown based on role (sidebar items, buttons, table columns)
- [ ] Firestore rules verified against all use cases
- [ ] Test all role combinations

---

## 16. Phase 4 — Polish & Excellence

**Duration estimate:** 2-3 weeks  
**Goal:** Export system, advanced features, performance, production readiness

### Phase 4 Checklist

#### 4.1 Export System
- [ ] PDF export for Pastor (records, approval logs, leaderboard)
- [ ] PDF export for Staff (own entries)
- [ ] CSV export for Admin (activity logs)
- [ ] Church logo and branding on all PDF exports
- [ ] Branded PDF header and footer
- [ ] Share via system share sheet (WhatsApp, email, etc.)
- [ ] Cloud Function for server-side complex PDF generation

#### 4.2 Partnership Period Summary Report
- [ ] Auto-trigger when a period is deactivated
- [ ] Summary PDF: total per arm, total partners, goal vs actual, top 10 contributors
- [ ] Stored in Firebase Storage and linked from period document

#### 4.3 Duplicate Entry Detection
- [ ] When staff submits an entry, check: same partner + same arm + same period + similar amount (within ±10%)
- [ ] Show warning: "A similar entry exists for [Partner] in this period. Continue?"
- [ ] Warning is advisory, not blocking

#### 4.4 Church Branding
- [ ] Settings screen for Admin: upload logo, set church name, choose primary color
- [ ] Logo stored in Firebase Storage
- [ ] Primary color applied to sidebar and key UI elements
- [ ] PDF exports use church logo

#### 4.5 Two-Factor Authentication
- [ ] Enable TOTP 2FA in Firebase Auth
- [ ] 2FA enrollment screen in Settings
- [ ] 2FA prompt on login when enrolled
- [ ] Recommended but not required for Pastor and Admin roles

#### 4.6 Advanced Notifications
- [ ] Batch pending approval notification (not one per entry — daily digest option)
- [ ] Goal milestone notifications (50%, 75%, 100% reached)
- [ ] Notification preferences in Settings (which events to receive)
- [ ] In-app notification center (bell icon → list of recent notifications)

#### 4.7 Performance Optimization
- [ ] Pagination on all lists (20 items per page)
- [ ] Firestore query cursors for pagination
- [ ] Firestore offline persistence configuration (enabled by default)
- [ ] Image optimization: compress before upload, use `cached_network_image`
- [ ] Lazy loading for large lists
- [ ] Widget rebuild optimization with `const` constructors

#### 4.8 Search & Filtering
- [ ] Global search within church data (Pastor only)
- [ ] Advanced filter panel on entries list
- [ ] Date range filter with calendar picker
- [ ] Amount range filter (min/max in Cedis)
- [ ] Multi-select arm filter
- [ ] Save filter preferences per session

#### 4.9 User Management
- [ ] Users list (Admin + Pastor): table with Name, Role, Email, Status, Last Active
- [ ] Deactivate/reactivate user
- [ ] Change user role (Pastor only can promote/demote)
- [ ] View user's entry history (Pastor)

#### 4.10 Accessibility & Localization
- [ ] Semantic labels on all interactive elements
- [ ] Sufficient color contrast (WCAG AA)
- [ ] Support system font scaling
- [ ] RTL support via Flutter's built-in RTL handling
- [ ] Localization setup (en_US base, easily extensible)
- [ ] Currency: GHS (Ghana Cedis) with ₵ symbol, 2 decimal places

#### 4.11 Onboarding
- [ ] First-run onboarding for new churches (Admin sets up church profile)
- [ ] "Getting Started" checklist on dashboard: Create first arm → Create first period → Set goals → Invite staff → Record first entry
- [ ] Help tooltips on key features

#### 4.12 Production Readiness
- [ ] Firebase App Check (anti-abuse)
- [ ] Crashlytics fully configured
- [ ] Analytics events for key user actions
- [ ] App review ready: TestFlight (iOS), Play Store Internal Track (Android)
- [ ] CI/CD pipeline: GitHub Actions → Firebase App Distribution
- [ ] Comprehensive README for project setup

---

## 17. Project Structure

```
the_pillr/
├── lib/
│   ├── main.dart
│   ├── firebase_options.dart
│   │
│   ├── core/
│   │   ├── theme/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_typography.dart
│   │   │   ├── app_spacing.dart
│   │   │   └── app_theme.dart
│   │   ├── router/
│   │   │   ├── app_router.dart
│   │   │   └── route_guards.dart
│   │   ├── constants/
│   │   │   ├── app_constants.dart
│   │   │   └── firebase_constants.dart
│   │   ├── utils/
│   │   │   ├── date_utils.dart
│   │   │   ├── currency_utils.dart
│   │   │   ├── validation_utils.dart
│   │   │   └── export_utils.dart
│   │   └── errors/
│   │       ├── app_exception.dart
│   │       └── error_handler.dart
│   │
│   ├── common/
│   │   ├── widgets/
│   │   │   ├── pillr_button.dart
│   │   │   ├── pillr_text_field.dart
│   │   │   ├── pillr_card.dart
│   │   │   ├── pillr_badge.dart
│   │   │   ├── pillr_stat_card.dart
│   │   │   ├── pillr_data_table.dart
│   │   │   ├── pillr_loading_shimmer.dart
│   │   │   ├── pillr_empty_state.dart
│   │   │   ├── pillr_error_state.dart
│   │   │   ├── pillr_searchable_dropdown.dart
│   │   │   ├── pillr_confirmation_dialog.dart
│   │   │   ├── pillr_progress_bar.dart
│   │   │   └── offline_banner.dart
│   │   └── layout/
│   │       ├── app_shell.dart
│   │       ├── adaptive_sidebar.dart
│   │       ├── adaptive_bottom_nav.dart
│   │       └── responsive_layout.dart
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   └── auth_repository.dart
│   │   │   ├── domain/
│   │   │   │   └── auth_state.dart
│   │   │   ├── providers/
│   │   │   │   └── auth_provider.dart
│   │   │   └── presentation/
│   │   │       ├── login_screen.dart
│   │   │       └── join_screen.dart
│   │   │
│   │   ├── dashboard/
│   │   │   ├── providers/
│   │   │   │   └── dashboard_provider.dart
│   │   │   └── presentation/
│   │   │       ├── pastor_dashboard_screen.dart
│   │   │       ├── staff_dashboard_screen.dart
│   │   │       └── admin_dashboard_screen.dart
│   │   │
│   │   ├── entries/
│   │   │   ├── data/
│   │   │   │   └── entries_repository.dart
│   │   │   ├── domain/
│   │   │   │   └── entry_model.dart
│   │   │   ├── providers/
│   │   │   │   └── entries_provider.dart
│   │   │   └── presentation/
│   │   │       ├── entries_list_screen.dart
│   │   │       ├── entry_form_screen.dart
│   │   │       ├── entry_detail_screen.dart
│   │   │       └── pending_approvals_screen.dart
│   │   │
│   │   ├── partners/
│   │   │   ├── data/
│   │   │   │   └── partners_repository.dart
│   │   │   ├── domain/
│   │   │   │   └── partner_model.dart
│   │   │   ├── providers/
│   │   │   │   └── partners_provider.dart
│   │   │   └── presentation/
│   │   │       ├── partners_list_screen.dart
│   │   │       ├── partner_profile_screen.dart
│   │   │       └── partner_form_screen.dart
│   │   │
│   │   ├── arms/
│   │   │   ├── data/arms_repository.dart
│   │   │   ├── domain/arm_model.dart
│   │   │   ├── providers/arms_provider.dart
│   │   │   └── presentation/arms_screen.dart
│   │   │
│   │   ├── periods/
│   │   │   ├── data/periods_repository.dart
│   │   │   ├── domain/period_model.dart
│   │   │   ├── providers/periods_provider.dart
│   │   │   └── presentation/periods_screen.dart
│   │   │
│   │   ├── goals/
│   │   │   ├── data/goals_repository.dart
│   │   │   ├── domain/goal_model.dart
│   │   │   ├── providers/goals_provider.dart
│   │   │   └── presentation/goals_screen.dart
│   │   │
│   │   ├── leaderboard/
│   │   │   ├── providers/leaderboard_provider.dart
│   │   │   └── presentation/leaderboard_screen.dart
│   │   │
│   │   ├── users/
│   │   │   ├── data/users_repository.dart
│   │   │   ├── domain/user_model.dart
│   │   │   ├── providers/users_provider.dart
│   │   │   └── presentation/
│   │   │       ├── users_list_screen.dart
│   │   │       └── invitations_screen.dart
│   │   │
│   │   ├── logs/
│   │   │   ├── data/logs_repository.dart
│   │   │   ├── domain/log_model.dart
│   │   │   ├── providers/logs_provider.dart
│   │   │   └── presentation/activity_logs_screen.dart
│   │   │
│   │   ├── settings/
│   │   │   └── presentation/settings_screen.dart
│   │   │
│   │   └── export/
│   │       ├── pdf_export_service.dart
│   │       └── csv_export_service.dart
│   │
│   └── services/
│       ├── firebase_service.dart
│       ├── notification_service.dart
│       ├── analytics_service.dart
│       └── connectivity_service.dart
│
├── functions/                       ← Firebase Cloud Functions
│   ├── src/
│   │   ├── index.ts
│   │   ├── auth/
│   │   │   ├── validateInviteCode.ts
│   │   │   ├── generateInviteCode.ts
│   │   │   └── completeRegistration.ts
│   │   ├── entries/
│   │   │   └── onEntryStatusChange.ts
│   │   ├── periods/
│   │   │   └── activatePeriod.ts
│   │   ├── scheduled/
│   │   │   └── expireInviteCodes.ts
│   │   └── email/
│   │       └── sendInviteEmail.ts
│   └── package.json
│
├── android/
├── ios/
├── web/
├── pubspec.yaml
├── firebase.json
├── firestore.rules
├── firestore.indexes.json
└── README.md
```

---

## 18. Environment & Configuration

### Firebase Project Setup Commands

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login
firebase login

# Initialize in project root
firebase init

# Select: Firestore, Functions, Storage, Emulators
# Use existing project: thepillr2 (already created — select this when prompted)

# Deploy rules
firebase deploy --only firestore:rules

# Deploy functions
firebase deploy --only functions

# Deploy everything
firebase deploy
```

### Firestore Indexes (firestore.indexes.json)

```json
{
  "indexes": [
    {
      "collectionGroup": "entries",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "churchId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "entries",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "churchId", "order": "ASCENDING" },
        { "fieldPath": "createdBy", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "entries",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "churchId", "order": "ASCENDING" },
        { "fieldPath": "partnershipPeriodId", "order": "ASCENDING" },
        { "fieldPath": "partnershipArmId", "order": "ASCENDING" },
        { "fieldPath": "amountCedis", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "partners",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "churchId", "order": "ASCENDING" },
        { "fieldPath": "totalApprovedAmount", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "activity_logs",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "churchId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "invite_codes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "churchId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" }
      ]
    }
  ]
}
```

### Resend Email Configuration (Cloud Function)

```typescript
// functions/src/email/sendInviteEmail.ts
import { Resend } from 'resend';

const resend = new Resend(process.env.RESEND_API_KEY);

export async function sendInviteEmail(
  toEmail: string,
  churchName: string,
  inviteCode: string,
  role: string,
  inviterName: string
) {
  await resend.emails.send({
    from: 'The Pillr <invites@pillr.app>',
    to: toEmail,
    subject: `You're invited to join ${churchName} on Pillr`,
    html: `
      <div style="font-family: Inter, sans-serif; max-width: 560px; margin: 0 auto;">
        <h2>You've been invited to The Pillr</h2>
        <p>${inviterName} has invited you to join <strong>${churchName}</strong> as a <strong>${role}</strong>.</p>
        <p>Your invitation code is:</p>
        <div style="background: #F3F4F6; padding: 24px; border-radius: 8px; text-align: center; margin: 24px 0;">
          <span style="font-size: 32px; font-weight: 700; letter-spacing: 4px; color: #1A56DB;">
            ${inviteCode}
          </span>
        </div>
        <p>This code expires in <strong>4 hours</strong>.</p>
        <a href="https://thepillr2.web.app/join?code=${inviteCode}" 
           style="display: inline-block; background: #1A56DB; color: white; 
                  padding: 12px 24px; border-radius: 8px; text-decoration: none;
                  font-weight: 600;">
          Accept Invitation
        </a>
        <p style="color: #6B7280; font-size: 14px; margin-top: 24px;">
          If you weren't expecting this invitation, you can ignore this email.
        </p>
      </div>
    `
  });
}
```

---

## 19. Original Design Conversation

> This section preserves the full design conversation for Cursor's context.

### Initial Brief

The app is called **The Pillr**.

**Core flow:**
Member gives → Staff records the partnership → Pastor approves → Record is added to approved and counts towards totals.

**Info for each entry:**
- Partnership arm
- Partnership period
- Amount in cedis
- Date given
- Bio data (the partner should be a searchable drop-down)
  - Member ID
  - Partner's Name
  - Fellowship
  - Email
  - Number
- If the member isn't available in the searchable drop-down, there should be a "Create New Partner" option

**Leaderboard** for only Pastor and financial head (staff).

### User Roles

**Admin (Tech Support)**
- Tech support for the app for a particular/each church, but can't view any data
- Can invite users
- Comprehensive logs of activities

**Pastor**
- Can view data, entries, leaderboard, partner bio data and all entries of that partner
- Can approve and decline, edit and update entries. Can see who made the entries
- Create and manage goals, partnership periods, partnership arms
- Can invite users
- Can make record entries

**Church Staff**
- Make record entries
- Can only view, edit, update and delete records they entered (still needs Pastor's approval after)

All users must be able to export data into a well-formatted PDF and CSV. Can export logs (Admin), Pastor: records and approval logs, leaderboard. Staff can export entries data.

**Multi-tenancy app for various churches.**

### Partnership Arms
Multiple arms. Examples: Venue, Rhapsody. Ability to add, delete, edit and toggle if active.

### Partnership Period
Ability to add, delete, edit and toggle if active. Only one can be active at a time.

### Invite System
There should be a sign-up page asking for invitation code and email. After the invite code matches what the admin sent over email, there should be an email invite. After the invite code is validated, the user is asked for the necessary data. On the admin side there should be a list of all the invite codes sent and status. Invite codes expire in 4 hours. There should be good authentication.

### Tech Stack Discussion

**Initial recommendation:** React Native + Expo + Supabase

**User's question:** What about Firebase and Flutter?

**Analysis provided:**

Flutter advantages for this project:
- Truly native performance on iOS and Android — Flutter compiles to native ARM code, not a JavaScript bridge
- Pixel-perfect consistency across platforms — identical look on iOS, Android, and Web
- Single codebase for mobile + web + desktop
- Material 3 design system built in
- Dart is a clean, strongly-typed language
- Better animation performance than React Native
- FlutterFire (official Flutter + Firebase SDK) is the most mature mobile backend integration

Firebase advantages for this project:
- Firestore real-time database is excellent for live leaderboards and approval status
- Offline-first by default — Firestore caches locally automatically
- Firebase Auth is battle-tested with email, magic links, OTP, 2FA
- Firebase Cloud Messaging (FCM) is the industry standard for push notifications
- FlutterFire SDK maturity is unmatched

Firebase limitations to be aware of:
- NoSQL requires careful data model design for relational data
- Firestore Security Rules require careful thought for complex role hierarchies
- Cost can scale with reads/writes on heavy leaderboard/approval flows
- No native SQL for complex reporting (handled via denormalization + Cloud Functions)

**Final decision: Flutter + Firebase**

Rationale: Mobile-first use case in church environments (potentially unreliable internet), real-time approval and leaderboard needs, FlutterFire's maturity, and Flutter's native performance make this the strongest choice.

Alternative considered: Flutter + Supabase (gets Flutter's native performance AND PostgreSQL's relational power) — worth noting as a fallback if Firestore's NoSQL model causes issues with reporting.

### UI Reference Images

Three reference screenshots were provided as the master UI aesthetic:

1. **Employee Management System** — Notion-style clean table with colored status dots, tab navigation, expandable rows
2. **Brightly Attendance Dashboard** — Left sidebar, 4-column stat cards, clean data table with avatar rows, status pills (green/red), pagination
3. **Zendenta Stock Management** — Collapsible sidebar with grouped sections, global search, horizontal color-coded progress bars, tabbed content, action buttons as dark pills

These images define the target visual quality. The app must feel like a premium, professional SaaS product. Clean, minimal, data-dense but not cluttered. White cards on a light gray page background. Primary brand color used sparingly for CTAs and active states. Status always communicated through color + icon + label (never just color alone for accessibility).

---

## Cursor Instructions

When building this project, follow these rules:

1. **Read this entire document first** before writing any code
2. **Build phase by phase** — do not skip to Phase 3 features during Phase 1 work
3. **Use the exact data models** from Section 7 — field names must match exactly as Firestore queries depend on them
4. **Deploy Firestore rules** from Section 8 before testing any data operations
5. **Every Firestore query must be scoped to `churches/{churchId}/...`** — never query a collection without the church scope
6. **Use Riverpod for all state** — no setState in feature screens, no BuildContext leaks
7. **Use GoRouter for all navigation** — no Navigator.push/pop except inside GoRouter's `builder`
8. **Follow the design system** — use only colors from `app_colors.dart`, only text styles from `app_typography.dart`
9. **Handle all three states** (loading/shimmer, data, error) on every screen that fetches data
10. **Write activity logs** for every user action that modifies data
11. **Test role isolation** — build a test checklist verifying each role can/cannot access each feature
12. **The currency is Ghana Cedis (₵ / GHS)** — format all amounts as `₵1,500.00`
13. **Partner search** uses Firestore queries, not client-side filtering — ensure indexes are deployed
14. **Real-time streams** everywhere that shows live data — use `.snapshots()` not `.get()`

---

*Document version 1.0 — Generated for The Pillr development team*  
*Stack: Flutter + Firebase | Platform: iOS, Android, Web*
