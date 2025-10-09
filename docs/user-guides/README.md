# CrystalShards Ecosystem - User Guides

Welcome to the CrystalShards ecosystem documentation! This comprehensive guide collection covers all four platforms in the Crystal community.

## Platform Overview

The CrystalShards ecosystem consists of four integrated platforms designed to support the Crystal programming language community:

1. **[CrystalShards.org](crystalshards.md)** - Package registry for Crystal libraries
2. **[CrystalDocs.org](crystaldocs.md)** - Automated documentation hosting
3. **[CrystalGigs.org](crystalgigs.md)** - Job board for Crystal developers
4. **[CrystalBits.org](crystalbits.md)** - Blog and newsletter platform

## Quick Start Guides

### For Crystal Developers

If you're building Crystal applications:
- Start with **[CrystalShards.org User Guide](crystalshards.md)** to learn how to find and use Crystal libraries
- Check **[CrystalDocs.org User Guide](crystaldocs.md)** to browse package documentation
- Visit **[CrystalBits.org User Guide](crystalbits.md)** for tutorials and community content

### For Library Authors

If you're creating Crystal libraries:
- Read the **[Publishing Guide](crystalshards.md#publishing-shards)** to share your work
- Learn about **[Documentation Generation](crystaldocs.md#for-library-authors)** best practices
- Follow **[Shard Guidelines](crystalshards.md#best-practices)** for quality packages

### For Employers

If you're hiring Crystal developers:
- Visit **[CrystalGigs.org User Guide](crystalgigs.md#for-employers)** to post job openings
- Learn about **[Job Posting Best Practices](crystalgigs.md#best-practices)**

### For Job Seekers

If you're looking for Crystal development work:
- Check **[CrystalGigs.org User Guide](crystalgigs.md#for-job-seekers)** for job search tips
- Browse **[Active Listings](crystalgigs.md#browsing-jobs)**

## Ecosystem Integration

All four platforms work together seamlessly:

```
┌─────────────────┐      ┌─────────────────┐
│ CrystalShards   │─────▶│ CrystalDocs     │
│ (Registry)      │      │ (Documentation) │
└─────────────────┘      └─────────────────┘
        │                         │
        │    Crystal Ecosystem    │
        │                         │
┌─────────────────┐      ┌─────────────────┐
│ CrystalGigs     │      │ CrystalBits     │
│ (Job Board)     │      │ (Blog/News)     │
└─────────────────┘      └─────────────────┘
```

**Integration Examples:**
- When you publish a shard to **CrystalShards**, documentation is automatically generated on **CrystalDocs**
- Job postings on **CrystalGigs** link to relevant shards and documentation
- Blog posts on **CrystalBits** reference packages and tutorials

## Getting Started

1. **Browse Packages**: Visit [CrystalShards.org](https://crystalshards.org) to explore available libraries
2. **Read Documentation**: Check [CrystalDocs.org](https://crystaldocs.org) for detailed API references
3. **Find Work**: Look for opportunities on [CrystalGigs.org](https://crystalgigs.org)
4. **Stay Informed**: Subscribe to [CrystalBits.org](https://crystalbits.org) newsletter

## Individual Platform Guides

### [CrystalShards.org User Guide](crystalshards.md)

The official Crystal package registry. Learn how to:
- Search and discover Crystal libraries (shards)
- Install dependencies in your projects
- Publish your own shards
- Manage shard versions
- Use the API for programmatic access

**Key Features:**
- Advanced search with filtering
- GitHub integration
- Automatic version tracking
- Download statistics
- Dependency resolution

### [CrystalDocs.org User Guide](crystaldocs.md)

Automated documentation hosting for Crystal packages. Covers:
- Browsing package documentation
- Version switching
- Documentation search
- Improving your shard's docs
- Understanding documentation builds

**Key Features:**
- Automatic doc generation
- Version navigation
- Full-text search
- Syntax highlighting
- Cross-referencing

### [CrystalGigs.org User Guide](crystalgigs.md)

Job board connecting Crystal developers with opportunities. Includes:
- Searching for Crystal jobs
- Posting job openings (for employers)
- Stripe payment integration
- Application tracking
- Job alerts

**Key Features:**
- Advanced job filtering
- Remote work options
- Salary transparency
- Direct application links
- Featured listings

### [CrystalBits.org User Guide](crystalbits.md)

Community blog and newsletter platform. Details:
- Reading technical articles
- Newsletter subscription
- Contributing content (if applicable)
- Discovering tutorials
- Community engagement

**Key Features:**
- Technical tutorials
- Community news
- Newsletter delivery
- Code highlighting
- Social sharing

## Ecosystem Overview

For a comprehensive understanding of how all platforms work together, see the **[Ecosystem Overview Guide](overview.md)**.

## API Documentation

All platforms provide REST APIs for programmatic access:

- **[CrystalShards API](../api/README.md)** - Package registry API
- **[CrystalDocs API](../api/README.md)** - Documentation API
- **[CrystalGigs API](../api/README.md)** - Job board API
- **[CrystalBits API](../api/README.md)** - Blog API

Complete OpenAPI specifications are available in the [API documentation directory](../api/).

## Community Resources

### Getting Help

- **Issues**: Report bugs on [GitHub](https://github.com/crystalshards/crystalshards)
- **Discussions**: Join the Crystal community forums
- **Support**: Email support@crystalshards.org

### Contributing

Want to contribute to the ecosystem?

- Check the [Contributing Guide](../../CLAUDE.md)
- Review [Development Guidelines](../../CLAUDE.md)
- Browse [Open Issues](https://github.com/crystalshards/crystalshards/issues)

### Crystal Language Resources

- **Official Website**: [crystal-lang.org](https://crystal-lang.org)
- **Crystal Docs**: [crystal-lang.org/docs](https://crystal-lang.org/docs)
- **Community**: [Crystal Forum](https://forum.crystal-lang.org)
- **GitHub**: [crystal-lang/crystal](https://github.com/crystal-lang/crystal)

## Frequently Asked Questions

### General Questions

**Q: Do I need an account to use CrystalShards?**
A: No, browsing and searching is completely open. You only need an account to publish shards.

**Q: Is CrystalShards free to use?**
A: Yes! All platforms are free except CrystalGigs job postings (paid to reduce spam).

**Q: How often is data updated?**
A: CrystalShards syncs with GitHub multiple times per day. Documentation builds happen automatically after shard updates.

**Q: Can I use the API without authentication?**
A: Yes, most read-only endpoints are public. Authentication is required for publishing and administrative operations.

### Technical Questions

**Q: What Crystal version is required?**
A: Crystal 1.0 or higher is recommended. Most shards specify their required version in `shard.yml`.

**Q: How do I report a malicious package?**
A: Email security@crystalshards.org with details. We take security seriously.

**Q: Can I host private shards?**
A: Not currently. CrystalShards hosts public packages only. For private dependencies, use Git URLs in your `shard.yml`.

### Platform-Specific Questions

See individual platform guides for detailed FAQs:
- [CrystalShards FAQ](crystalshards.md#troubleshooting)
- [CrystalDocs FAQ](crystaldocs.md#troubleshooting)
- [CrystalGigs FAQ](crystalgigs.md#faq--support)
- [CrystalBits FAQ](crystalbits.md#faq)

## Version History

- **v1.0.0** (2025-10-09) - Initial user guide release
- Platform continues to evolve - check individual guides for latest features

## Feedback

We value your feedback! Help us improve these guides:

- Report documentation issues: [GitHub Issues](https://github.com/crystalshards/crystalshards/issues)
- Suggest improvements: Create a pull request
- Ask questions: support@crystalshards.org

---

**Last Updated**: 2025-10-09
**Documentation Version**: 1.0.0
