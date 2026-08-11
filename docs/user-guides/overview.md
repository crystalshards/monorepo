# CrystalShards Ecosystem Overview

## Introduction

The CrystalShards ecosystem is a comprehensive suite of platforms designed to support the Crystal programming language community. This guide provides a holistic view of how all four platforms work together to create a thriving ecosystem.

## The Four Platforms

### Platform Summary

```
┌─────────────────────────────────────────────────┐
│                                                 │
│        The CrystalShards Ecosystem              │
│                                                 │
│  ┌─────────────┐        ┌─────────────┐        │
│  │CrystalShards│───────▶│ CrystalDocs │        │
│  │  Registry   │        │    Docs     │        │
│  └─────────────┘        └─────────────┘        │
│         │                      │                │
│         │   Community Hub      │                │
│         │                      │                │
│  ┌─────────────┐        ┌─────────────┐        │
│  │ CrystalGigs │        │ CrystalBits │        │
│  │  Job Board  │        │   Blog      │        │
│  └─────────────┘        └─────────────┘        │
│                                                 │
└─────────────────────────────────────────────────┘
```

**1. CrystalShards.org - Package Registry**
- **Purpose**: Central repository for Crystal libraries (shards)
- **Key Features**: Search, discovery, publishing, version management
- **Users**: All Crystal developers
- **Analogous to**: rubygems.org, npmjs.com, crates.io

**2. CrystalDocs.org - Documentation Platform**
- **Purpose**: Automatically generated API documentation hosting
- **Key Features**: Version switching, search, cross-references
- **Users**: Library consumers and authors
- **Analogous to**: docs.rs, rubydoc.info

**3. CrystalGigs.org - Job Board**
- **Purpose**: Connecting Crystal developers with employment opportunities
- **Key Features**: Job listings, application tracking, Stripe payments
- **Users**: Job seekers and employers
- **Analogous to**: Rust Jobs, Ruby on Rails Jobs

**4. CrystalBits.org - Blog & Newsletter**
- **Purpose**: Community content, tutorials, and updates
- **Key Features**: Technical articles, weekly newsletter, community news
- **Users**: Everyone learning or working with Crystal
- **Analogous to**: This Week in Rust, Ruby Weekly

## How They Work Together

### Integration Flow

```
Developer Journey:
┌─────────────────────────────────────────────────┐
│ 1. Discover on CrystalShards                    │
│    ↓ Find a library for your project            │
│ 2. Read Docs on CrystalDocs                     │
│    ↓ Understand API and usage                   │
│ 3. Learn from CrystalBits                       │
│    ↓ Tutorial on best practices                 │
│ 4. Find Work on CrystalGigs                     │
│    ↓ Apply Crystal skills professionally        │
└─────────────────────────────────────────────────┘

Library Author Journey:
┌─────────────────────────────────────────────────┐
│ 1. Publish on CrystalShards                     │
│    ↓ Make library discoverable                  │
│ 2. Auto-docs on CrystalDocs                     │
│    ↓ Documentation generated automatically      │
│ 3. Featured on CrystalBits                      │
│    ↓ Write about your library                   │
│ 4. Hire via CrystalGigs                         │
│    ↓ Find contributors or users                 │
└─────────────────────────────────────────────────┘
```

### Real-World Example

Let's follow a typical workflow:

**Scenario: Building a Web Application**

1. **Need a web framework**
   - Visit **CrystalShards.org**
   - Search for "web framework"
   - Find Kemal and Lucky frameworks
   - Compare downloads, stars, and activity

2. **Learn how to use it**
   - Click "Documentation" link
   - Redirects to **CrystalDocs.org**
   - Browse API reference
   - Read method documentation
   - Copy code examples

3. **Follow a tutorial**
   - See blog post featured on **CrystalBits.org**
   - "Building Your First Lucky App"
   - Step-by-step guide with examples
   - Subscribe to newsletter for more

4. **Build your application**
   - Install shard: `shards install`
   - Write code using documentation
   - Deploy to production

5. **Look for work**
   - Visit **CrystalGigs.org**
   - Find "Lucky Framework Developer" position
   - Apply with your new project in portfolio
   - Get hired!

6. **Give back to community**
   - Build and publish your own shard
   - Write tutorial on **CrystalBits.org**
   - Eventually post jobs on **CrystalGigs.org**

### Cross-Platform Features

**Unified Search:**
- Search shards on CrystalShards
- Find related docs on CrystalDocs
- Discover tutorials on CrystalBits
- Locate jobs using those technologies

**Consistent Identity:**
- Single sign-on across platforms (coming soon)
- Unified profile
- Activity tracking
- Contribution history

**Integrated Navigation:**
- Quick links between platforms
- Contextual recommendations
- Related content suggestions
- Ecosystem-wide notifications

## Platform Details

### CrystalShards.org

**Primary Use Cases:**

1. **Finding Libraries**
   ```crystal
   # Need HTTP client?
   # Search: "http client"
   # Find: crest, http.cr, halite

   dependencies:
     crest:
       github: mamantoha/crest
       version: ~> 1.3.0
   ```

2. **Publishing Libraries**
   ```bash
   # Create shard
   git tag v1.0.0
   git push origin v1.0.0

   # Submit to registry
   # Visit CrystalShards.org → "Publish Shard"
   # Enter GitHub URL
   ```

3. **Tracking Dependencies**
   - View dependency trees
   - Check for updates
   - Monitor security issues
   - See reverse dependencies

**Best For:**
- Initial library discovery
- Comparing alternatives
- Version management
- Community metrics

### CrystalDocs.org

**Primary Use Cases:**

1. **API Reference**
   ```crystal
   # Looking up method signatures
   HTTP::Server#bind_tcp(host : String, port : Int32)

   # Understanding parameters
   # Reading examples
   # Checking return types
   ```

2. **Learning Library APIs**
   - Browse class hierarchy
   - Understand module organization
   - See usage examples
   - Follow type links

3. **Version Comparison**
   - Compare v1.0 vs v2.0
   - Identify breaking changes
   - Plan migrations
   - Test compatibility

**Best For:**
- Detailed API understanding
- Code reference while developing
- Migration planning
- Understanding type systems

### CrystalGigs.org

**Primary Use Cases:**

1. **Job Searching (Seekers)**
   ```
   Filters:
   - Remote: Yes
   - Salary: $120k+
   - Type: Full-time
   - Experience: Senior

   Results: 15 Crystal positions
   ```

2. **Hiring (Employers)**
   ```
   Post Job:
   - Title: Senior Crystal Developer
   - Salary: $140k-180k
   - Location: Remote
   - Cost: $99/30 days
   ```

3. **Career Development**
   - See market trends
   - Understand salary ranges
   - Identify skills in demand
   - Network with companies

**Best For:**
- Career opportunities
- Hiring Crystal developers
- Market research
- Community connections

### CrystalBits.org

**Primary Use Cases:**

1. **Learning**
   ```
   Tutorial: "Building REST APIs in Crystal"
   - Step-by-step guide
   - Full code examples
   - Best practices
   - Common pitfalls
   ```

2. **Staying Updated**
   ```
   Newsletter (Weekly):
   - Crystal 1.10 released
   - New shards this week
   - Community highlights
   - Job postings
   ```

3. **Knowledge Sharing**
   - Write tutorials
   - Share experiences
   - Document patterns
   - Showcase projects

**Best For:**
- Learning new concepts
- Staying current
- Deep-dive articles
- Community engagement

## User Personas

### The Beginner

**Name**: Alex, new to Crystal
**Journey:**

1. **Discover** (CrystalBits)
   - Reads "Getting Started with Crystal"
   - Subscribes to newsletter
   - Learns basic concepts

2. **Explore** (CrystalShards)
   - Searches for beginner-friendly shards
   - Installs Kemal web framework
   - Browses popular libraries

3. **Learn** (CrystalDocs)
   - Reads Kemal documentation
   - Follows API examples
   - Understands routing

4. **Build**
   - Creates first web app
   - Publishes to GitHub
   - Shares on social media

### The Library Author

**Name**: Jordan, experienced developer
**Journey:**

1. **Create**
   - Builds useful library
   - Writes documentation
   - Creates examples

2. **Publish** (CrystalShards)
   - Submits to registry
   - Tags releases
   - Sets up webhooks

3. **Document** (CrystalDocs)
   - Automatically generated
   - Reviews for completeness
   - Improves doc comments

4. **Promote** (CrystalBits)
   - Writes announcement post
   - Explains use cases
   - Shares tutorial

5. **Support**
   - Responds to issues
   - Updates documentation
   - Releases new versions

### The Job Seeker

**Name**: Sam, looking for opportunities
**Journey:**

1. **Learn** (CrystalBits)
   - Reads advanced tutorials
   - Follows industry trends
   - Builds portfolio

2. **Explore** (CrystalShards)
   - Contributes to popular shards
   - Publishes own libraries
   - Gains visibility

3. **Network** (Community)
   - Engages on forums
   - Attends virtual meetups
   - Builds reputation

4. **Apply** (CrystalGigs)
   - Finds perfect position
   - Submits application
   - Showcases Crystal work

### The Employer

**Name**: Taylor, hiring manager
**Journey:**

1. **Research** (CrystalBits)
   - Understands Crystal ecosystem
   - Reads case studies
   - Evaluates fit

2. **Post** (CrystalGigs)
   - Creates detailed job listing
   - Offers competitive salary
   - Features position

3. **Review** (CrystalShards)
   - Checks candidates' published shards
   - Reviews code quality
   - Assesses expertise

4. **Hire**
   - Interviews candidates
   - Makes offer
   - Onboards new developer

## Technical Architecture

### Infrastructure

All platforms share:

**Common Infrastructure:**
- Cloud Run services that scale to zero when idle
- Cloud SQL for PostgreSQL
- Cloud Storage for documentation artifacts and shard packages
- Cloud Tasks for background work
- Secret Manager for credentials
- One global external Application Load Balancer, with Cloud DNS holding the zones
- Cloud Logging and Cloud Monitoring

**Technology Stack:**
- **Language**: Crystal
- **Framework**: Lucky (web framework)
- **Database**: PostgreSQL
- **Storage**: Cloud Storage
- **Search**: PostgreSQL full-text (with potential Meilisearch upgrade)

**Deployment:**
- Infrastructure as Code (Terraform), applied in CI
- Automated CI/CD
- Container images in Artifact Registry
- Automatic scaling, down to zero when idle

### Data Flow

```
┌────────────────────────────────────────────┐
│ User Action                                │
└───────────┬────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────┐
│ Web Application (Lucky on Cloud Run)       │
│ - Route handling                           │
│ - Business logic                           │
│ - Authentication                           │
└───────────┬────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────┐
│ Database (Cloud SQL PostgreSQL)            │
│ - Relational data                          │
│ - Full-text search                         │
│ - Transactions                             │
└───────────┬────────────────────────────────┘
            │
            ▼
┌────────────────────────────────────────────┐
│ Storage (Cloud Storage)                    │
│ - Documentation files                      │
│ - Shard packages                           │
│ - Static assets                            │
└────────────────────────────────────────────┘
```

### Security

**Authentication:**
- JWT-based authentication
- GitHub OAuth integration
- API tokens with scopes
- Rate limiting per user

**Data Protection:**
- HTTPS everywhere (TLS 1.3)
- Encrypted at rest (Cloud SQL, Cloud Storage)
- Encrypted in transit
- Regular security audits

**Isolation:**
- Sandboxed documentation builds: the build job runs untrusted shard code under a service account that holds no permissions
- The build job reads its input and writes its output through signed URLs, so it never holds a credential
- Each application has its own database on the shared PostgreSQL instance

## Getting the Most Out of the Ecosystem

### For Developers

**Daily Workflow:**

1. **Morning**: Check CrystalBits newsletter
2. **Development**: Reference CrystalDocs
3. **Discovery**: Browse CrystalShards
4. **Career**: Monitor CrystalGigs

**Tips:**
- Bookmark frequently used documentation
- Subscribe to CrystalBits for updates
- Set GitHub watch on important shards
- Create job alerts on CrystalGigs

### For Library Authors

**Publishing Checklist:**

```
□ Create comprehensive README
□ Write good doc comments
□ Include usage examples
□ Publish to CrystalShards
□ Verify docs on CrystalDocs
□ Write announcement on CrystalBits
□ Share with community
```

**Promotion Strategy:**
1. Publish to CrystalShards (visibility)
2. Ensure docs are complete (usability)
3. Write tutorial on CrystalBits (education)
4. Engage with community (support)

### For Employers

**Hiring Strategy:**

```
1. Post on CrystalGigs
   - Clear requirements
   - Competitive salary
   - Remote-friendly

2. Engage on CrystalBits
   - Sponsor content
   - Share tech blog posts
   - Showcase Crystal usage

3. Contribute to Ecosystem
   - Open source shards
   - Support community
   - Build reputation
```

## Community Guidelines

### Code of Conduct

All platforms follow the Crystal community Code of Conduct:

**Be Respectful:**
- Treat everyone with respect
- Welcome diverse perspectives
- Assume good intentions
- Help newcomers

**Be Constructive:**
- Provide helpful feedback
- Focus on the issue, not the person
- Share knowledge generously
- Collaborate openly

**Be Professional:**
- No harassment or discrimination
- No spam or self-promotion
- Respect privacy
- Follow platform rules

### Reporting Issues

**Technical Issues:**
- GitHub Issues for each platform
- Detailed bug reports
- Steps to reproduce
- Version information

**Abuse/Violations:**
- abuse@crystalshards.org
- Quick response
- Confidential handling
- Fair investigation

**Security Issues:**
- security@crystalshards.org
- Responsible disclosure
- No public issues
- Coordinated fixes

## Future Roadmap

### Planned Features

**CrystalShards:**
- Security vulnerability scanning
- Dependency update notifications
- Private shard hosting (enterprise)
- Enhanced search with ML

**CrystalDocs:**
- Interactive examples
- Version diff viewer
- Custom themes
- Offline documentation

**CrystalGigs:**
- Job alerts via email
- Company profiles
- Applicant tracking
- Interview scheduling

**CrystalBits:**
- Comment system
- Author profiles
- Content translation
- Video content

### Community Input

Want to influence the roadmap?

- Vote on feature requests
- Submit proposals
- Contribute code
- Sponsor development

Contact: roadmap@crystalshards.org

## Support & Resources

### Getting Help

**Platform-Specific:**
- CrystalShards: support@crystalshards.org
- CrystalDocs: support@crystaldocs.org
- CrystalGigs: support@crystalgigs.org
- CrystalBits: support@crystalbits.org

**General Ecosystem:**
- Email: hello@crystalshards.org
- Status: status.crystalshards.org
- GitHub: github.com/crystalshards

**Community Support:**
- Crystal Forum: forum.crystal-lang.org
- Discord/Slack: Links on crystal-lang.org
- Stack Overflow: Tag `crystal-lang`

### Contributing

All platforms are open source:

```bash
# Clone monorepo
git clone https://github.com/crystalshards/monorepo

# Apps are in:
cd apps/crystalshards
cd apps/crystaldocs
cd apps/crystalgigs
cd apps/crystalbits
```

**Ways to Contribute:**
- Report bugs
- Fix issues
- Write documentation
- Create tutorials
- Improve design
- Sponsor hosting

See [CONTRIBUTING.md](../../CLAUDE.md) for guidelines.

## Conclusion

The CrystalShards ecosystem provides a complete platform for the Crystal community:

- **Discover** libraries on CrystalShards
- **Learn** from CrystalDocs and CrystalBits
- **Build** amazing applications
- **Connect** with opportunities on CrystalGigs
- **Contribute** back to the ecosystem

Together, these platforms make Crystal development more accessible, efficient, and enjoyable for everyone.

Welcome to the Crystal community! 💎

---

**Last Updated**: 2025-10-09
**Guide Version**: 1.0.0

For questions or feedback: hello@crystalshards.org
