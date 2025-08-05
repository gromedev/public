# Complete GIAM Power BI Demo Creation Guide

> **Transform your CSV data into an impressive executive dashboard - no SQL required!**

## 🎯 Executive Summary

You have 2 months of daily CSV snapshots containing AD and Entra ID data. This guide will help you create a compelling Power BI demo showing:

- **Current identity landscape** (users, groups, permissions)
- **Historical trends** (60 days of changes)
- **Security insights** (admin access, group memberships)
- **Cross-platform relationships** (AD ↔ Entra correlation)

**Time Investment:** 2-6 hours depending on complexity desired

-----

## 📋 Prerequisites & Data Preparation

### Required Files (Latest Date)

```
✅ GIAM-ADUsers-BasicData_YYYYMMDD.csv
✅ GIAM-ADUsers-GroupInfo_YYYYMMDD.csv  
✅ GIAM-EntraUsers-BasicData_YYYYMMDD.csv
✅ GIAM-EntraUsers-Permissions_YYYYMMDD.csv
✅ GIAM-EntraUsers-Groups_YYYYMMDD.csv
```

### File Organization (Recommended)

```
/PowerBI_Demo/
├── Current/          # Latest files
├── Historical/       # Daily snapshots by date
│   ├── 2024-01-15/
│   ├── 2024-01-16/
│   └── ...
└── PowerBI_Demo.pbix # Your Power BI file
```

### Key Data Columns to Verify

- **UserIdentifier**: Your linking field across all tables
- **Date fields**: Properly formatted (YYYY-MM-DD)
- **Boolean fields**: 1/0 or True/False consistently

-----

## 🚀 Phase 1: Power BI Setup & Data Import (30 minutes)

### Step 1: Install & Open Power BI Desktop

1. Download from Microsoft (free)
1. Open Power BI Desktop
1. Choose “Blank Report”

### Step 2: Import Current Data

1. **Home tab** → **Get Data** → **Text/CSV**
1. **Import each CSV file:**
   
   **Import Order & Naming:**
   
   ```
   File → Rename Table To:
   GIAM-ADUsers-BasicData → "ADUsers"
   GIAM-ADUsers-GroupInfo → "ADGroups" 
   GIAM-EntraUsers-BasicData → "EntraUsers"
   GIAM-EntraUsers-Permissions → "EntraPermissions"
   GIAM-EntraUsers-Groups → "EntraGroups"
   ```
1. **For each import:**
- Click **Transform Data**
- Check data types (UserIdentifier = Text)
- Remove empty rows: **Transform** → **Remove Rows** → **Remove Empty Rows**
- Click **Close & Apply**

### Step 3: Data Quality Check

**Quick validation in Data view:**

- Count of UserIdentifier in each table
- No null values in key fields
- Date formats consistent

-----

## 🔗 Phase 2: Create Data Relationships (15 minutes)

### Access Model View

- Click **Model** icon (left sidebar)
- You’ll see your tables as boxes

### Create Relationships (Drag & Drop)

```
Primary Relationships:
ADUsers[UserIdentifier] ← → EntraUsers[UserIdentifier]

Secondary Relationships:  
ADUsers[UserIdentifier] ← → ADGroups[UserIdentifier]
EntraUsers[UserIdentifier] ← → EntraPermissions[UserIdentifier]
EntraUsers[UserIdentifier] ← → EntraGroups[UserIdentifier]
```

### Relationship Settings

- **Cardinality**: Many to Many (for demo purposes)
- **Cross filter direction**: Both (enables bidirectional filtering)
- **Make active**: Yes

-----

## 📊 Phase 3: Essential Demo Visualizations

### Page 1: Executive Overview Dashboard

#### Top Row: Key Metrics (Card Visuals)

**Card 1: Total AD Users**

- Visualization: Card
- Field: `ADUsers[UserIdentifier]`
- Aggregation: Count (Distinct)

**Card 2: Total Entra Users**

- Visualization: Card
- Field: `EntraUsers[UserIdentifier]`
- Aggregation: Count (Distinct)

**Card 3: Hybrid Users**

- Create New Measure (Home → New Measure):

```dax
Hybrid Users = 
CALCULATE(
    DISTINCTCOUNT(ADUsers[UserIdentifier]),
    ADUsers[UserIdentifier] IN VALUES(EntraUsers[UserIdentifier])
)
```

**Card 4: Cloud-Only Users**

- Create New Measure:

```dax
Cloud Only Users = 
DISTINCTCOUNT(EntraUsers[UserIdentifier]) - [Hybrid Users]
```

#### Middle Row: Distribution Charts

**Donut Chart: User Distribution**

- Legend: Create calculated column

```dax
User Type = 
IF(
    ADUsers[UserIdentifier] IN VALUES(EntraUsers[UserIdentifier]),
    "Hybrid",
    IF(
        ADUsers[UserIdentifier] <> BLANK(),
        "AD Only", 
        "Cloud Only"
    )
)
```

- Values: Count of UserIdentifier

**Donut Chart: Account Status**

- Legend: `ADUsers[Enabled]`
- Values: Count of UserIdentifier
- Format: Change 0/1 to “Disabled”/“Enabled”

#### Bottom Row: Group Analysis

**Bar Chart: Top 10 Groups**

- Y-axis: `ADGroups[Group]`
- X-axis: Count of `ADGroups[UserIdentifier]`
- Sort: Descending by count
- Top N filter: 10

**Stacked Column: Group Types**

- X-axis: `ADGroups[GroupCategory]`
- Y-axis: Count of UserIdentifier
- Legend: `ADGroups[GroupCategory]`

### Page 2: Security & Permissions Dashboard

#### Admin Access Analysis

**Table: High-Risk Users**

- Rows: `EntraPermissions[UserIdentifier]`
- Columns: `EntraPermissions[ActiveRoles]`, `EntraPermissions[EligibleRoles]`
- Filter: `EntraPermissions[ActiveRoles]` contains “Admin”

**Matrix: Permission Distribution**

- Rows: `EntraPermissions[UserIdentifier]`
- Columns: `EntraPermissions[ActiveRoles]`
- Values: Count of entries

**Stacked Bar: Active vs Eligible Roles**

- Y-axis: `EntraPermissions[ActiveRoles]`
- X-axis: Count of UserIdentifier
- Legend: Create measure to separate Active/Eligible

#### Security Metrics Cards

**Admin Users Count**

```dax
Admin Users = 
CALCULATE(
    DISTINCTCOUNT(EntraPermissions[UserIdentifier]),
    CONTAINSSTRING(EntraPermissions[ActiveRoles], "Admin")
)
```

**Privileged Access Percentage**

```dax
Admin Percentage = 
DIVIDE([Admin Users], DISTINCTCOUNT(EntraUsers[UserIdentifier]), 0) * 100
```

### Page 3: Group & Membership Analysis

**Treemap: Group Sizes**

- Category: `ADGroups[Group]`
- Values: Count of `ADGroups[UserIdentifier]`

**Scatter Plot: Group Complexity**

- X-axis: Group member count
- Y-axis: Count of groups per user
- Legend: `ADGroups[GroupCategory]`

**Network Diagram** (if available in your Power BI version)

- Relationships between users and groups

-----

## 📈 Phase 4: Historical Trends (Advanced - 1 hour)

### Option A: Simple Historical Comparison

**Import Additional Dates:**

1. Import CSVs from 30 days ago as separate tables
1. Name them `ADUsers_30Days`, `EntraUsers_30Days`
1. Create comparison measures:

```dax
User Growth (30 days) = 
DISTINCTCOUNT(ADUsers[UserIdentifier]) - 
DISTINCTCOUNT(ADUsers_30Days[UserIdentifier])

Growth Percentage = 
DIVIDE([User Growth (30 days)], DISTINCTCOUNT(ADUsers_30Days[UserIdentifier]), 0) * 100
```

### Option B: Full Historical Analysis

**Combine Historical Files:**

1. **Get Data** → **Folder**
1. Select your Historical folder
1. **Combine & Transform** → **Combine Files**
1. Add custom column for date extraction:

```
Date = Date.FromText(Text.BetweenDelimiters([Name], "_", "."))
```

**Time Series Visualizations:**

**Line Chart: User Growth Over Time**

- X-axis: Date
- Y-axis: Count of UserIdentifier
- Legend: Data source (AD/Entra)

**Area Chart: Permission Trends**

- X-axis: Date
- Y-axis: Count of permissions
- Legend: ActiveRoles vs EligibleRoles

**Stacked Column: Monthly Group Changes**

- X-axis: Date (by month)
- Y-axis: Count of group memberships
- Legend: Group type

-----

## 🎭 Phase 5: Demo Presentation Strategy

### Demo Flow (5-7 minutes max)

#### Slide 1: “Executive Overview” (1 minute)

**Opening Hook:** *“Here’s our complete identity landscape at a glance”*

- Point to total user counts
- Highlight hybrid vs cloud-only split
- **Key Message**: “We have complete visibility across platforms”

#### Slide 2: “Security Posture” (2 minutes)

**Transition:** *“Now let’s dive into who has what access”*

- Show admin user count and percentage
- Highlight specific high-risk accounts
- Demo filtering by permission type
- **Key Message**: “Every privileged account is tracked and monitored”

#### Slide 3: “Group Management” (2 minutes)

**Transition:** *“Groups are where complexity lives”*

- Show largest groups
- Demonstrate group type distribution
- Point out nested group relationships
- **Key Message**: “We understand our group complexity”

#### Slide 4: “Historical Insights” (2 minutes)

**Transition:** *“Here’s the power of daily data collection”*

- Show user growth trends
- Highlight any significant changes/events
- Demonstrate ability to track changes over time
- **Key Message**: “Data-driven identity governance in action”

### Pro Demo Tips

**Storytelling Elements:**

- Start with business impact numbers
- Use “we discovered” language for insights
- Point out anomalies or interesting patterns
- End with “what this enables us to do”

**Technical Preparation:**

- Test all filters and interactions
- Have backup static screenshots
- Practice navigation between pages
- Prepare for “what if” questions

**Executive Talking Points:**

- **Compliance**: “Daily automated reporting for audits”
- **Security**: “Immediate visibility into access changes”
- **Efficiency**: “No more manual user/group counting”
- **Future**: “Foundation for real-time governance”

-----

## 🔧 Advanced Features & Customization

### Enhanced DAX Measures

**Stale Account Detection:**

```dax
Stale Accounts = 
CALCULATE(
    DISTINCTCOUNT(ADUsers[UserIdentifier]),
    ADUsers[LastLogonTimestamp] < TODAY() - 90
)
```

**Permission Risk Score:**

```dax
Risk Score = 
SWITCH(
    TRUE(),
    CONTAINSSTRING(EntraPermissions[ActiveRoles], "Global Admin"), 10,
    CONTAINSSTRING(EntraPermissions[ActiveRoles], "Admin"), 7,
    CONTAINSSTRING(EntraPermissions[ActiveRoles], "Manager"), 4,
    1
)
```

**Group Membership Density:**

```dax
Avg Groups Per User = 
DIVIDE(
    COUNT(ADGroups[UserIdentifier]),
    DISTINCTCOUNT(ADGroups[UserIdentifier]),
    0
)
```

### Visual Formatting Tips

**Professional Appearance:**

- Use organization brand colors
- Apply consistent fonts (Segoe UI recommended)
- Round numbers appropriately (1.2K vs 1,234)
- Use conditional formatting for risk indicators

**Interactive Elements:**

- Add slicers for date ranges
- Include drill-through pages for details
- Use bookmarks for demo navigation
- Set up highlight actions between visuals

-----

## ⏱️ Time Investment Guide

### Quick Demo (2 hours)

- Import current data only
- Basic cards and charts
- Simple relationships
- Executive overview page

### Comprehensive Demo (4 hours)

- All current data visualizations
- Security and permissions analysis
- Group relationship mapping
- Professional formatting

### Full Historical Analysis (6 hours)

- Complete historical data integration
- Time series analysis
- Advanced DAX measures
- Multiple demo scenarios

-----

## 🚨 Troubleshooting Common Issues

### Data Import Problems

**Issue**: CSV encoding errors or special characters
**Solution**: Open CSV in Excel, Save As UTF-8, then import

**Issue**: Date fields not recognized
**Solution**: Transform data → Change Type → Date

**Issue**: UserIdentifier has leading/trailing spaces
**Solution**: Transform → Trim

### Relationship Problems

**Issue**: Relationships won’t create
**Solution**: Check data types match (both Text or both Number)

**Issue**: Cross-filtering not working
**Solution**: Set relationship to bidirectional

### Performance Issues

**Issue**: Slow refresh or visualization
**Solution**:

- Limit historical data to last 60 days
- Remove unused columns
- Use DirectQuery for large datasets

### Visualization Problems

**Issue**: Charts showing wrong data
**Solution**: Check aggregation settings (Sum vs Count vs Average)

**Issue**: Filters not working
**Solution**: Verify relationship directions and active relationships

-----

## 📋 Pre-Demo Checklist

### Data Validation

- [ ] All CSV files imported successfully
- [ ] UserIdentifier counts match expectations
- [ ] No obvious data quality issues
- [ ] Relationships created and tested

### Visualization Check

- [ ] All charts display data correctly
- [ ] Filters work as expected
- [ ] Colors and formatting professional
- [ ] Page navigation smooth

### Demo Preparation

- [ ] Story flow practiced (under 7 minutes)
- [ ] Backup screenshots prepared
- [ ] Key talking points memorized
- [ ] Answers ready for expected questions

### Technical Setup

- [ ] Power BI Desktop updated
- [ ] Presentation mode tested
- [ ] Screen resolution optimized
- [ ] Internet connection stable (if using cloud features)

-----

## 🎯 Success Metrics for Your Demo

### Immediate Impact

- **Audience engagement**: Questions about specific insights
- **Executive interest**: Requests for regular reporting
- **Technical credibility**: Recognition of data quality and scope

### Follow-up Opportunities

- **Resource allocation**: Approval for SQL backend development
- **Stakeholder expansion**: Other departments wanting similar analysis
- **Process integration**: Requests to integrate with existing workflows

### Long-term Value

- **Governance framework**: Foundation for identity governance program
- **Compliance reporting**: Automated audit trail capabilities
- **Security monitoring**: Baseline for anomaly detection

-----

## 🚀 Next Steps After Demo Success

### Immediate (Week 1)

- Export key insights as static reports
- Document data refresh procedures
- Plan regular reporting schedule

### Short-term (Month 1)

- Automate data import processes
- Add more historical data
- Create department-specific views

### Long-term (Quarter 1)

- Implement SQL Server backend
- Add real-time data streaming
- Integrate with SIEM/security tools
- Develop automated alerting

-----

## 📞 Quick Reference

### Essential DAX Functions

- `DISTINCTCOUNT()` - Unique user counts
- `CALCULATE()` - Filtered calculations
- `DIVIDE()` - Safe division (no errors)
- `CONTAINSSTRING()` - Text pattern matching
- `TODAY()` - Current date calculations

### Key Visualizations

- **Cards**: KPI metrics
- **Donut Charts**: Distribution/categories
- **Bar Charts**: Rankings and comparisons
- **Line Charts**: Trends over time
- **Tables/Matrix**: Detailed data

### Demo Do’s and Don’ts

**Do:**

- Keep it under 7 minutes
- Focus on business value
- Have backup plans
- Practice beforehand
- Use organization terminology

**Don’t:**

- Get lost in technical details
- Show data quality issues
- Navigate aimlessly
- Ignore your audience
- Promise features you don’t have

-----

**Good luck with your demo! You have excellent data - now make it shine! 🌟**