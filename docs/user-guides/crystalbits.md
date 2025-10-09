# CrystalBits.org User Guide

## Table of Contents

- [Introduction](#introduction)
- [Reading Posts](#reading-posts)
- [Newsletter](#newsletter)
- [For Authors](#for-authors)
- [Engagement](#engagement)
- [FAQ](#faq)

## Introduction

### What is CrystalBits.org?

CrystalBits.org is the community blog and newsletter platform for the Crystal programming language ecosystem. It's your source for:

- Technical tutorials and guides
- Crystal language updates
- Community news and events
- Shard (library) spotlights
- Best practices and patterns
- Performance tips and tricks
- Real-world case studies

Think of it as the "Crystal Weekly" newsletter combined with an evergreen blog of Crystal knowledge.

### Content Focus

**Technical Content:**
- Beginner tutorials
- Advanced techniques
- Performance optimization
- Design patterns in Crystal
- Concurrency and parallelism
- Type system deep-dives

**Community Content:**
- New shard releases
- Conference talks
- Community spotlights
- Job market trends
- Ecosystem updates
- Events and meetups

**Practical Guides:**
- Building web applications
- Database integration
- API development
- Testing strategies
- Deployment guides
- Monitoring and debugging

### Why CrystalBits?

**For Readers:**
- Curated, high-quality content
- Crystal-specific knowledge
- Learn from experts
- Stay updated on ecosystem
- Discover new libraries

**For the Ecosystem:**
- Knowledge sharing
- Community building
- Onboard new developers
- Showcase Crystal capabilities
- Document best practices

## Reading Posts

### Homepage

Visit [https://crystalbits.org](https://crystalbits.org) to browse content:

```
┌─────────────────────────────────────────────┐
│ 🔍 Search Articles                           │
│ ┌─────────────────────────────────────────┐ │
│ │ Search posts...                          │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ ⭐ Featured Post                             │
│ ┌─────────────────────────────────────────┐ │
│ │ Building High-Performance APIs          │ │
│ │ Learn how to optimize Crystal APIs...   │ │
│ │ 📅 Oct 7, 2025 • 👁️ 1,234 views       │ │
│ └─────────────────────────────────────────┘ │
├─────────────────────────────────────────────┤
│ 📚 Recent Posts                              │
│ • Crystal 1.10 Released: What's New         │
│ • Async Programming Patterns in Crystal     │
│ • Shard Spotlight: Lucky Framework          │
│ • Optimizing PostgreSQL Queries             │
└─────────────────────────────────────────────┘
```

### Browsing Posts

**Navigation Options:**

1. **Recent Posts** (default view)
   - Newest content first
   - Scroll to load more
   - Infinite scroll enabled

2. **Featured Posts**
   - Highlighted quality content
   - Editor's picks
   - Popular tutorials

3. **Popular Posts**
   - Most viewed this week
   - All-time popular
   - Trending content

4. **By Category** (if implemented)
   - Tutorials
   - News
   - Case Studies
   - Shard Spotlights

### Searching Posts

**Search Functionality:**

Type in the search box to find:
- Keywords in title: "performance", "async", "web"
- Content search: searches full post body
- Author names: find posts by specific authors
- Tags: filter by topics

**Search Tips:**
```
"crystal async"           → Posts about async programming
"tutorial" + "beginner"   → Beginner tutorials
"performance optimization" → Performance guides
author:"Jane Doe"         → Posts by Jane Doe (if supported)
```

### Understanding Post Cards

Each post preview shows:

```
┌────────────────────────────────────────┐
│ Building High-Performance APIs         │
│ ────────────────────────────────────── │
│ Learn how to optimize your Crystal     │
│ APIs for maximum throughput using...   │
│                                        │
│ 🏷️ tutorial • performance • api       │
│ 📅 October 7, 2025                     │
│ ✍️ Jane Smith                          │
│ 👁️ 1,234 views • 📖 8 min read        │
└────────────────────────────────────────┘
```

- **Title**: Post headline
- **Excerpt**: Preview of content
- **Tags**: Topic categorization
- **Date**: Publication date
- **Author**: Content creator
- **Stats**: View count and reading time

### Reading a Post

Click any post to view full content:

**Post Header:**
```
┌────────────────────────────────────────────┐
│ Building High-Performance APIs             │
│                                            │
│ By Jane Smith • October 7, 2025           │
│ 8 min read • 1,234 views                  │
│ 🏷️ tutorial, performance, api            │
└────────────────────────────────────────────┘
```

**Post Content:**
- Formatted markdown
- Syntax-highlighted code
- Embedded images/diagrams
- Section headings
- Internal/external links

**Post Footer:**
```
┌────────────────────────────────────────────┐
│ 💌 Enjoyed this post?                      │
│ Subscribe to our newsletter for weekly    │
│ Crystal content!                           │
│                                            │
│ 🔗 Share: [Twitter] [Reddit] [HN]         │
└────────────────────────────────────────────┘
```

### Code Examples in Posts

All code samples include:

**Syntax Highlighting:**
```crystal
# Crystal code is beautifully formatted
class APIServer
  def initialize(@port : Int32)
    @server = HTTP::Server.new do |context|
      handle_request(context)
    end
  end

  def start
    @server.bind_tcp "0.0.0.0", @port
    @server.listen
  end
end
```

**Copy Button:**
- Hover over code block
- Click copy icon
- Code copied to clipboard

**Language Labels:**
- Shows language: Crystal, Shell, YAML, etc.
- Helps with multi-language posts

### View Count Tracking

View counts update automatically:
- First visit counts as view
- Subsequent visits within 24 hours don't re-count
- Helps identify popular content
- No personal data collected

## Newsletter

### Why Subscribe?

**Weekly Digest Includes:**
- Latest blog posts
- Crystal ecosystem updates
- New shard releases
- Community events
- Job postings from CrystalGigs
- Curated links and resources

**Benefits:**
- Never miss important updates
- Delivered to your inbox
- Unsubscribe anytime
- No spam, just quality content
- Mobile-friendly format

### Subscribing

**Sign Up Process:**

1. **Enter Email**
   ```
   ┌──────────────────────────────────────┐
   │ 💌 Subscribe to CrystalBits          │
   │ ┌────────────────────────────────┐   │
   │ │ your@email.com                 │   │
   │ └────────────────────────────────┘   │
   │ [Subscribe]                          │
   └──────────────────────────────────────┘
   ```

2. **Confirmation Email**
   - Check your inbox
   - Look for "Confirm your subscription"
   - Click confirmation link
   - Prevents spam subscriptions

3. **Subscription Active**
   - Confirmation page shown
   - First newsletter at next scheduled send
   - Usually weekly (Mondays)

**Subscribe From:**
- Homepage footer
- End of any blog post
- Dedicated /subscribe page

### Email Format

**Newsletter Structure:**

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CrystalBits Weekly - October 9, 2025
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📰 This Week's Highlights

• Crystal 1.10 Released with Performance Improvements
• New Tutorial: Building Microservices
• Shard Spotlight: crystal-pg

📝 Latest Posts

[Title] Building High-Performance APIs
      Learn optimization techniques...
      → Read more: [link]

[Title] Async Programming Patterns
      Master Crystal's concurrency...
      → Read more: [link]

💼 Crystal Jobs

• Senior Crystal Developer - Tech Corp ($140k-180k)
• Backend Engineer - Startup Inc. (Remote)
  → View all jobs: crystalgigs.org

🔧 New Shards

• awesome-shard v1.0 - Description
• another-lib v0.5 - Description

📅 Upcoming Events

• Crystal Meetup - Virtual, Oct 15
• Conference Talk - Nov 1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Unsubscribe | Update Preferences | Web Version
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Newsletter Frequency

**Current Schedule:**
- **Weekly digest**: Every Monday morning
- **Special editions**: Major announcements
- **No spam**: Quality over quantity

**What Triggers Emails:**
- Regular schedule (weekly)
- Major Crystal releases
- Important ecosystem news
- Critical security updates (rare)

### Managing Subscription

**Update Preferences:**
- Link in every email footer
- Choose content types
- Adjust frequency (if options available)
- Change email address

**Temporary Pause:**
Not currently available - unsubscribe and resubscribe when ready.

### Unsubscribing

**Easy Unsubscribe:**

1. Open any newsletter email
2. Click "Unsubscribe" link in footer
3. Confirm on landing page
4. Immediately removed from list

**Confirmation Page:**
```
✓ You've been unsubscribed

Sorry to see you go! You will no longer receive
the CrystalBits newsletter.

Change your mind? [Re-subscribe]
```

**Privacy:**
- Unsubscribe removes email from database
- No re-subscription without opt-in
- GDPR compliant

## For Authors

### Content Guidelines

**Ideal Content for CrystalBits:**

✅ **Good Content:**
- Original tutorials
- Real-world case studies
- Performance benchmarks
- Design pattern discussions
- Crystal ecosystem news
- Technical deep-dives
- Practical how-tos

❌ **Not Suitable:**
- Pure marketing/ads
- Off-topic content
- Plagiarized material
- AI-generated without review
- Extremely short posts (<300 words)
- Link-only posts

### Writing for CrystalBits

**If Contributing is Open:**

**Submission Process:**

1. **Prepare Content**
   - Write in Markdown
   - Include code examples
   - Add clear explanations
   - Proofread carefully

2. **Submit Post**
   - Use submission form (if available)
   - Or email: submissions@crystalbits.org
   - Include:
     - Title
     - Content (Markdown)
     - Author name
     - Author email
     - Tags (suggested)

3. **Review Process**
   - Editorial review (1-3 days)
   - Feedback provided
   - Revisions if needed
   - Publication scheduled

4. **Publication**
   - Post goes live
   - Featured in newsletter
   - Social media promotion
   - Author credited

**Currently:**
Check if submissions are open at [crystalbits.org/submit](https://crystalbits.org/submit) or contact submissions@crystalbits.org.

### Markdown Syntax

**Formatting Guide:**

**Headings:**
```markdown
# Main Title (H1)
## Section (H2)
### Subsection (H3)
```

**Emphasis:**
```markdown
*italic text*
**bold text**
***bold and italic***
```

**Code:**
````markdown
Inline code: `variable_name`

Code block:
```crystal
def hello
  puts "Hello, Crystal!"
end
```
````

**Lists:**
```markdown
Unordered:
- Item one
- Item two

Ordered:
1. First step
2. Second step
```

**Links:**
```markdown
[Link text](https://example.com)
[CrystalShards](https://crystalshards.org)
```

**Images:**
```markdown
![Alt text](https://example.com/image.png)
```

**Quotes:**
```markdown
> This is a blockquote.
> It can span multiple lines.
```

### Code Highlighting

**Supported Languages:**
- `crystal` - Crystal code (primary)
- `yaml` - Configuration files
- `bash` / `sh` - Shell commands
- `json` - JSON data
- `sql` - Database queries
- `html` - HTML markup
- `css` - Stylesheets

**Best Practices:**
```crystal
# ✅ Good: Clear, commented, complete
class User
  def initialize(@name : String)
  end

  # Returns a greeting message
  def greet : String
    "Hello, #{@name}!"
  end
end

user = User.new("Alice")
puts user.greet  # => Hello, Alice!
```

```crystal
# ❌ Avoid: Unclear, no context
def x(y)
  z = ...
end
```

## Engagement

### Comments (If Implemented)

If commenting is enabled:

**Posting Comments:**
1. Scroll to end of post
2. Enter name and email
3. Write thoughtful comment
4. Submit

**Comment Guidelines:**
- Be respectful
- Stay on topic
- Add value to discussion
- No spam or self-promotion
- No offensive content

**Moderation:**
- Comments reviewed before posting
- Spam filtered automatically
- Report inappropriate comments

### Social Sharing

**Share Posts:**

Every post includes share buttons:
- Twitter/X
- Reddit
- Hacker News
- LinkedIn
- Copy link

**Why Share:**
- Help grow Crystal community
- Spread knowledge
- Support content creators
- Attract new developers

### Community Guidelines

**When Engaging:**

✅ **Do:**
- Be respectful and kind
- Ask questions
- Share experiences
- Provide constructive feedback
- Help others learn
- Give credit where due

❌ **Don't:**
- Harass or bully
- Post spam
- Share malicious content
- Plagiarize
- Engage in trolling
- Make discriminatory comments

**Reporting:**
Email abuse@crystalbits.org to report:
- Spam
- Harassment
- Inappropriate content
- Security vulnerabilities

## FAQ

### General Questions

**Q: Is CrystalBits official?**
A: Yes, it's part of the official CrystalShards ecosystem, maintained by community members.

**Q: How often is new content published?**
A: We aim for 2-3 posts per week, plus weekly newsletter.

**Q: Is the newsletter free?**
A: Yes! Completely free, no ads, no spam.

**Q: Can I read posts without subscribing?**
A: Absolutely! All content is freely accessible. Newsletter is optional.

**Q: Do you accept guest posts?**
A: Check [crystalbits.org/submit](https://crystalbits.org/submit) or email submissions@crystalbits.org for current policy.

**Q: How do I suggest a topic?**
A: Email ideas@crystalbits.org with your suggestion.

### Newsletter Questions

**Q: How do I change my email address?**
A: Unsubscribe the old email, subscribe with the new one. Or email support@crystalbits.org.

**Q: I'm not receiving the newsletter. Why?**
A:
- Check spam/junk folder
- Verify you clicked confirmation link
- Add noreply@crystalbits.org to contacts
- Email support@crystalbits.org if issue persists

**Q: Can I get past newsletters?**
A: Web versions are available at [crystalbits.org/newsletter/archive](https://crystalbits.org/newsletter/archive).

**Q: What day are newsletters sent?**
A: Weekly newsletters go out every Monday morning (UTC).

**Q: Is my email shared with third parties?**
A: Never. We respect your privacy. See [Privacy Policy](https://crystalbits.org/privacy).

### Content Questions

**Q: Can I republish posts elsewhere?**
A: With attribution and link back to original, yes. Check license at bottom of each post.

**Q: How do I report an error in a post?**
A: Email corrections@crystalbits.org with post URL and details.

**Q: Are posts written by AI?**
A: All posts are written by humans, though AI tools may assist with editing.

**Q: Can I translate posts to other languages?**
A: Yes! Email translations@crystalbits.org to coordinate.

**Q: Where can I find older posts?**
A: Browse the archive at [crystalbits.org/archive](https://crystalbits.org/archive).

### Technical Questions

**Q: What license is the content under?**
A: Typically CC BY-SA 4.0 unless otherwise noted. Check individual posts.

**Q: Can I get posts via RSS?**
A: Yes! RSS feed at [crystalbits.org/feed.xml](https://crystalbits.org/feed.xml).

**Q: Is there an API?**
A: Yes, see [API documentation](../api/README.md) for programmatic access.

**Q: Do you track readers?**
A: Minimal analytics for view counts. No personal data collected. Privacy-focused.

### Getting Help

**General Support:**
Email: support@crystalbits.org

**Content Submissions:**
Email: submissions@crystalbits.org

**Newsletter Issues:**
Email: newsletter@crystalbits.org

**Report Abuse:**
Email: abuse@crystalbits.org

**Privacy Concerns:**
Email: privacy@crystalbits.org

**Response Time:**
- General: 1-2 business days
- Abuse reports: Within 24 hours
- Newsletter issues: Within 48 hours

## Next Steps

### For Readers

- **Browse Posts**: [https://crystalbits.org](https://crystalbits.org)
- **Subscribe**: Get weekly updates delivered
- **Follow on Social**: [@crystalbits](https://twitter.com/crystalbits)
- **Share**: Help spread Crystal knowledge

### For Authors

- **Check Submissions**: [crystalbits.org/submit](https://crystalbits.org/submit)
- **Email Ideas**: submissions@crystalbits.org
- **Read Guidelines**: Review content requirements
- **Start Writing**: Prepare your tutorial or article

### Community

- **Join Discussion**: [Crystal Forum](https://forum.crystal-lang.org)
- **Find Shards**: [CrystalShards.org](https://crystalshards.org)
- **Read Docs**: [CrystalDocs.org](https://crystaldocs.org)
- **Find Jobs**: [CrystalGigs.org](https://crystalgigs.org)

## Additional Resources

- **Crystal Language**: [crystal-lang.org](https://crystal-lang.org)
- **Crystal Book**: [crystal-lang.org/reference](https://crystal-lang.org/reference)
- **Community**: [crystal-lang.org/community](https://crystal-lang.org/community)
- **GitHub**: [github.com/crystal-lang/crystal](https://github.com/crystal-lang/crystal)

---

**Last Updated**: 2025-10-09
**Guide Version**: 1.0.0

For feedback or corrections, please [open an issue](https://github.com/crystalshards/crystalbits/issues).
