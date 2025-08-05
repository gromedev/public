# GIAM Power BI Demo Guide - Based on Your Actual Data Structure

> **Tailored specifically for your CSV outputs and data collection system**

## 🎯 Your Data Assets (What You Actually Have)

Based on your codebase analysis, you’re collecting these CSV files daily:

### Core Identity Data

```
✅ GIAM-ADUsers-BasicData_YYYYMMDD.csv
   └── UserIdentifier, DistinguishedName, ObjectSid, Enabled, Manager, 
       ExtensionAttribute2, WhenCreated, LastLogonTimestamp, LogonCount, 
       PasswordLastChange, PasswordNeverExpires, TrustedForDelegation

✅ GIAM-ADUsers-GroupInfo_YYYYMMDD.csv  
   └── UserIdentifier, Group, GroupCategory, GroupDistinguishedName

✅ GIAM-EntraUsers-BasicData_YYYYMMDD.csv
   └── UserIdentifier, UserPrincipalName, Id, accountEnabled, UserType, 
       assignedLicenses, CustomSecurityAttributes, createdDateTime, 
       LastSignInDateTime, OnPremisesSyncEnabled, OnPremisesSamAccountName

✅ GIAM-EntraUsers-Permissions_YYYYMMDD.csv
   └── UserIdentifier, UserPrincipalName, ActiveRoles, EligibleRoles

✅ GIAM-EntraUsers-Groups_YYYYMMDD.csv
   └── UserIdentifier, UPN, GroupName, GroupRoleAssignable, GroupType, 
       GroupMembershipType, GroupSecurityEnabled, MembershipPath

✅ GIAM-EntraUsers-GraphPermissions_YYYYMMDD.csv
   └── UserIdentifier, UserPrincipalName, PermissionType, Permission, 
       ResourceId, ClientAppId

✅ GIAM-HRAPI_YYYYMMDD.csv
   └── UserIdentifier, employeegroupname

✅ GIAM-EntraGroupCount_YYYYMMDD.csv
   └── GroupIdentifier, membershipCount
```

**Key Insight**: UserIdentifier is your golden thread - it’s the part before @ in UPNs, linking everything together!

-----

## 🚀 Power BI Import Strategy (Your Specific Files)

### Import Order & Table Naming

```
1. GIAM-ADUsers-BasicData → "AD_Users"
2. GIAM-ADUsers-GroupInfo → "AD_Groups" 
3. GIAM-EntraUsers-BasicData → "Entra_Users"
4. GIAM-EntraUsers-Permissions → "Entra_Permissions"
5. GIAM-EntraUsers-Groups → "Entra_Groups"
6. GIAM-EntraUsers-GraphPermissions → "Graph_Permissions"
7. GIAM-HRAPI → "HR_Data"
8. GIAM-EntraGroupCount → "Group_Sizes"
```

### Data Relationships (Based on Your Schema)

```
Central Hub: AD_Users[UserIdentifier] 
├── AD_Groups[UserIdentifier]
├── Entra_Users[UserIdentifier] 
├── Entra_Permissions[UserIdentifier]
├── Entra_Groups[UserIdentifier]
├── Graph_Permissions[UserIdentifier]
└── HR_Data[UserIdentifier]

Secondary: Group_Sizes[GroupIdentifier] ← → AD_Groups[Group]
```

-----

## 📊 High-Impact Visualizations (Using Your Actual Columns)

### Page 1: Identity Landscape Overview

#### Executive Cards (Top Row)

**Total AD Users**

```dax
AD Users = DISTINCTCOUNT(AD_Users[UserIdentifier])
```

**Total Entra Users**

```dax
Entra Users = DISTINCTCOUNT(Entra_Users[UserIdentifier])
```

**Hybrid Users (Your Unique Insight!)**

```dax
Hybrid Users = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[UserIdentifier] IN VALUES(Entra_Users[UserIdentifier])
)
```

**Sync Status (OnPrem vs Cloud)**

```dax
Synced Users = 	
CALCULATE(
    DISTINCTCOUNT(Entra_Users[UserIdentifier]),
    Entra_Users[OnPremisesSyncEnabled] = TRUE()
)
```

#### Distribution Charts

**Donut: Account Status**

- Legend: `AD_Users[Enabled]` (your 0/1 field)
- Values: Count of UserIdentifier
- **Demo Impact**: “X% of accounts are disabled but still exist”

**Stacked Bar: User Types**

- Y-axis: `Entra_Users[UserType]` (Member/Guest)
- X-axis: Count of UserIdentifier
- **Demo Impact**: “External user governance visibility”

**Column Chart: License Distribution**

- X-axis: `Entra_Users[assignedLicenses]` (split by |)
- Y-axis: Count of UserIdentifier
- **Demo Impact**: “License optimization opportunities”

### Page 2: Security & Permissions Deep Dive

#### Privileged Access Analysis

**Table: Active Admin Roles**

- Rows: `Entra_Permissions[UserIdentifier]`
- Columns: `Entra_Permissions[ActiveRoles]`, `Entra_Permissions[EligibleRoles]`
- Filter: ActiveRoles contains “Admin”
- **Demo Impact**: “Every admin account visible and tracked”

**Matrix: Graph API Permissions**

- Rows: `Graph_Permissions[UserIdentifier]`
- Columns: `Graph_Permissions[Permission]`
- Values: `Graph_Permissions[PermissionType]`
- **Demo Impact**: “API access governance - who can do what”

**Stacked Column: PIM vs Permanent**

```dax
Active Admin Count = 
CALCULATE(
    DISTINCTCOUNT(Entra_Permissions[UserIdentifier]),
    Entra_Permissions[ActiveRoles] <> BLANK(),
    CONTAINSSTRING(Entra_Permissions[ActiveRoles], "Admin")
)

Eligible Admin Count = 
CALCULATE(
    DISTINCTCOUNT(Entra_Permissions[UserIdentifier]),
    Entra_Permissions[EligibleRoles] <> BLANK(),
    CONTAINSSTRING(Entra_Permissions[EligibleRoles], "Admin")
)
```

#### Security Metrics Cards

**Stale Accounts (Using Your LastLogonTimestamp)**

```dax
Stale Accounts = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[LastLogonTimestamp] < TODAY() - 90
)
```

**Never Logged On**

```dax
Never Logged On = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[LastLogonTimestamp] = BLANK()
)
```

**Privileged Delegation Risk**

```dax
Trusted for Delegation = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[TrustedForDelegation] = 1
)
```

### Page 3: Group Management & HR Integration

#### Group Analysis (Using Your Actual Group Data)

**Treemap: Largest Groups**

- Category: `Group_Sizes[GroupIdentifier]`
- Values: `Group_Sizes[membershipCount]`
- **Demo Impact**: “Group bloat identification”

**Stacked Bar: Group Types**

- Y-axis: `AD_Groups[GroupCategory]` (your enhanced group types)
- X-axis: Count of UserIdentifier
- Legend: `Entra_Groups[GroupType]` (Security/Distribution/Microsoft 365)

**Scatter Plot: Direct vs Inherited Membership**

- X-axis: Count where `Entra_Groups[MembershipPath] = "Direct"`
- Y-axis: Count where `Entra_Groups[MembershipPath] = "Inherited"`
- **Demo Impact**: “Nested group complexity visualization”

#### HR Integration Insights

**Matrix: Department Group Membership**

- Rows: `HR_Data[employeegroupname]`
- Columns: `AD_Groups[Group]` (top 20)
- Values: Count of UserIdentifier
- **Demo Impact**: “Business alignment with technical groups”

**Card: HR-IT Alignment**

```dax
Users with HR Data = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[UserIdentifier] IN VALUES(HR_Data[UserIdentifier])
)

HR Coverage = DIVIDE([Users with HR Data], [AD Users], 0)
```

### Page 4: Historical Trends (Your 60-Day Advantage!)

#### Import Historical Data Strategy

```powershell
# Your file naming convention enables easy historical analysis
GIAM-ADUsers-BasicData_20241201_143022.csv
GIAM-ADUsers-BasicData_20241202_143022.csv
# Extract date from filename pattern: YYYYMMDD
```

#### Trend Visualizations

**Line Chart: User Growth Over Time**

- X-axis: Date (extracted from filename)
- Y-axis: `DISTINCTCOUNT(UserIdentifier)`
- Legend: Data source (AD vs Entra)
- **Demo Impact**: “Cloud adoption journey visualization”

**Area Chart: Permission Changes**

- X-axis: Date
- Y-axis: Count of `Entra_Permissions[ActiveRoles]`
- **Demo Impact**: “Privilege creep monitoring”

**Stacked Column: Account Lifecycle**

- X-axis: Date (weekly buckets)
- Y-axis: Count of new accounts (`WhenCreated` within week)
- Legend: `Entra_Users[UserType]`

**Line Chart: Security Posture Trends**

```dax
Admin Ratio by Date = 
DIVIDE(
    [Active Admin Count],
    DISTINCTCOUNT(Entra_Users[UserIdentifier]),
    0
) * 100
```

-----

## 🎭 Demo Storyline (Based on Your Data)

### Opening Hook (30 seconds)

*“We collect identity data from 3 systems daily - Active Directory, Entra ID, and HR. Here’s what 60 days of automated governance looks like…”*

### Act 1: The Big Picture (90 seconds)

**Show Executive Overview Page**

- **“We manage [X] users across on-premises and cloud”**
- **”[Y]% are hybrid identities - synchronized between systems”**
- **”[Z] external users with governed access”**
- **Point to license distribution**: *“Immediate cost optimization visibility”*

### Act 2: Security Deep Dive (2 minutes)

**Switch to Security Page**

- **“Every privileged account is tracked”** - show admin table
- **”[X] users have admin roles, [Y] have eligible roles through PIM”**
- **Show stale accounts**: *”[Z] accounts haven’t logged in for 90+ days”*
- **Graph permissions**: *“API access governance - who can read what”*
- **Filter demonstration**: *“Watch me drill down to specific admin types”*

### Act 3: Business Alignment (90 seconds)

**Switch to Group/HR Page**

- **“Technical groups aligned with business structure”** - show HR matrix
- **“Largest groups identified for cleanup”** - point to treemap
- **“Nested group complexity mapped”** - show direct vs inherited
- **Filter by department**: *“Each business unit’s access patterns”*

### Act 4: Historical Intelligence (90 seconds)

**Switch to Trends Page**

- **“60 days of continuous monitoring”** - show growth trends
- **“Permission changes tracked automatically”** - show privilege trends
- **“Security posture improvement measured”** - show admin ratio changes
- **Point to specific events**: *“Here’s when we cleaned up stale accounts”*

### Closing Impact (30 seconds)

*“This is automated, daily identity governance. No manual reports, no guesswork. Every privileged account, every group membership, every access change - tracked and visualized for immediate action.”*

-----

## 🔥 Your Unique Demo Advantages

### 1. Cross-Platform Correlation

**What others don’t have**: Most organizations can’t correlate AD and Entra data
**Your advantage**: UserIdentifier links everything - show hybrid user analysis

### 2. Historical Depth

**What others don’t have**: Point-in-time manual reports
**Your advantage**: 60 days of continuous data - show trends and changes

### 3. HR Integration

**What others don’t have**: Technical data in isolation
**Your advantage**: Business context with employeegroupname correlation

### 4. Graph Permissions Visibility

**What others don’t have**: API access blind spots
**Your advantage**: Graph_Permissions table shows application access patterns

### 5. Automated Collection Maturity

**What others don’t have**: Manual, inconsistent data gathering
**Your advantage**: Daily automated collection with timestamp precision

-----

## 📋 Specific DAX Measures for Your Data

### Identity Hygiene Measures

```dax
Password Never Expires = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[PasswordNeverExpires] = 1
)

Accounts Never Used = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[LogonCount] = 0
)

Recently Created = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    AD_Users[WhenCreated] >= TODAY() - 30
)
```

### Governance Measures

```dax
Orphaned AD Accounts = 
CALCULATE(
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    NOT(AD_Users[UserIdentifier] IN VALUES(Entra_Users[UserIdentifier])),
    NOT(AD_Users[UserIdentifier] IN VALUES(HR_Data[UserIdentifier]))
)

Unmanaged Groups = 
CALCULATE(
    DISTINCTCOUNT(AD_Groups[Group]),
    AD_Groups[Group] IN VALUES(Group_Sizes[GroupIdentifier]),
    Group_Sizes[membershipCount] = 0
)
```

### Business Intelligence Measures

```dax
Manager Coverage = 
DIVIDE(
    CALCULATE(DISTINCTCOUNT(AD_Users[UserIdentifier]), AD_Users[Manager] <> BLANK()),
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    0
)

ExtensionAttribute2 Usage = 
DIVIDE(
    CALCULATE(DISTINCTCOUNT(AD_Users[UserIdentifier]), AD_Users[ExtensionAttribute2] <> BLANK()),
    DISTINCTCOUNT(AD_Users[UserIdentifier]),
    0
)
```

-----

## ⚡ Quick Implementation Steps

### Hour 1: Basic Setup

1. Import latest CSV files (all 8 types)
1. Create relationships using UserIdentifier
1. Build executive overview cards
1. Test hybrid user calculation

### Hour 2: Security Focus

1. Create admin permissions table
1. Build stale account measures
1. Add Graph permissions matrix
1. Test filtering and drill-down

### Hour 3: Business Context

1. Import HR data and create department matrix
1. Add group size treemap
1. Build membership path analysis
1. Test cross-filtering between technical and business views

### Hour 4: Historical Magic

1. Import 30-day-old files as comparison tables
1. Create growth and change measures
1. Build trend visualizations
1. Add date-based filtering

-----

## 🎯 Executive Questions You’ll Get (And Your Answers)

**Q: “How accurate is this data?”**
**A**: *“Updated daily through automated collection. Last refresh: [show timestamp]. UserIdentifier correlation ensures consistency across systems.”*

**Q: “What about security?”**  
**A**: *“Every admin account tracked in real-time. [X] privileged users, [Y] through PIM. Graph API permissions visible down to application level.”*

**Q: “Can we see historical changes?”**
**A**: *“60 days of continuous monitoring. Here’s user growth, permission changes, group modifications - all automated.”*

**Q: “How does this help with compliance?”**
**A**: *“Automated audit trail. Never logged on accounts, stale access, orphaned identities - all visible for immediate remediation.”*

**Q: “What’s next?”**
**A**: *“SQL backend in development for real-time dashboards. This proves our governance maturity and data quality.”*

-----

## 🚨 Demo Day Checklist

### Data Validation

- [ ] Latest CSV files imported (check timestamps)
- [ ] UserIdentifier counts match across tables
- [ ] No obvious nulls in key fields (Enabled, UserType, etc.)
- [ ] Historical comparison data loaded

### Measure Testing

- [ ] Hybrid Users calculation works
- [ ] Admin counts match manual verification
- [ ] Stale account logic validated
- [ ] HR correlation percentages reasonable

### Visual Verification

- [ ] All charts display data correctly
- [ ] Cross-filtering works between pages
- [ ] Group treemap shows expected large groups
- [ ] Trend lines show logical progression

### Narrative Preparation

- [ ] Opening hook practiced
- [ ] Key numbers memorized (total users, admins, etc.)
- [ ] Transition phrases ready
- [ ] Closing impact statement rehearsed

-----

**Your data collection system is already impressive - now make it shine in Power BI! 🌟**