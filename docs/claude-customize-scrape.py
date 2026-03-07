# claude.ai/customize — structured scrape
# Scraped 2026-03-06
# Source: browser automation of https://claude.ai/customize

connector_details = {
    "Context7": {
        "connected": False,
        "no_disconnect_button": True,
        "description": "Context7 fetches up-to-date code examples and documentation right into your LLM's context. No tab-switching, no hallucinated APIs that don't exist, no outdated code generation.",
        "tool_permissions": {
            "read_only_tools": {
                "count": 2,
                "default_permission": "Always allow",
                "tools": [
                    {"name": "query-docs", "permission": "auto-allow"},
                    {"name": "resolve-library-id", "permission": "auto-allow"}
                ]
            }
        }
    },
    "GitHub": {
        "connected": True,
        "disconnect_button": True,
        "description": None,
        "tool_permissions": None,
        "note": "Detail panel showed only the Disconnect button with no tool list or description visible"
    },
    "Gmail": {
        "connected": True,
        "disconnect_button": True,
        "description": "Connect Gmail to Claude to quickly find important emails and understand long conversations. Claude can search through your messages, read entire email threads to give you context, and help you stay on top of your inbox. Perfect for finding that message you remember sending, catching up on email chains you missed, or preparing for meetings.",
        "tool_permissions": {
            "read_only_tools": {
                "count": 6,
                "default_permission": "Always allow",
                "tools": [
                    {"name": "Get Gmail Profile", "permission": "auto-allow"},
                    {"name": "List Gmail Drafts", "permission": "auto-allow"},
                    {"name": "List Gmail Labels", "permission": "auto-allow"},
                    {"name": "Read Gmail Email", "permission": "auto-allow"},
                    {"name": "Read Gmail Thread", "permission": "auto-allow"},
                    {"name": "Search Gmail Emails", "permission": "auto-allow"}
                ]
            },
            "write_delete_tools": {
                "count": 1,
                "default_permission": "Needs approval",
                "tools": [
                    {"name": "Create Gmail Draft", "permission": "needs-approval"}
                ]
            }
        }
    },
    "Google Calendar": {
        "connected": True,
        "disconnect_button": True,
        "description": "Connect Google Calendar to Claude to view your schedule, manage events, and coordinate meetings. Claude can search your calendar for events, check your availability, find free time slots, create and update events, respond to invitations, and help you prepare for meetings. Useful for understanding what's coming up, scheduling new meetings by finding mutual availability, managing your calendar by creating or updating events, coordinating schedules across multiple people, or preparing for meetings by reviewing attendee lists and details.",
        "tool_permissions": {
            "read_only_tools": {
                "count": 5,
                "default_permission": "Always allow",
                "tools": [
                    {"name": "Find Meeting Times", "permission": "auto-allow"},
                    {"name": "Find Free Time", "permission": "auto-allow"},
                    {"name": "Get Event Details", "permission": "auto-allow"},
                    {"name": "List Calendars", "permission": "auto-allow"},
                    {"name": "List Calendar Events", "permission": "auto-allow"}
                ]
            },
            "write_delete_tools": {
                "count": 4,
                "default_permission": "Custom",
                "tools": [
                    {"name": "Create Calendar Event", "permission": "needs-approval"}
                ],
                "note": "Only first write tool visible; 3 more below fold"
            }
        }
    },
    "Google Drive": {
        "connected": True,
        "disconnect_button": True,
        "has_view_details_button": True,
        "description": "Connect Google Drive to Claude so it can search through your documents, read file contents, and help you work with your files. Claude can find specific documents even when you don't remember the exact name, read and analyze the content of your docs, and convert files to different formats. Useful for finding old project notes, analyzing document content, or pulling information from files scattered across your Drive.",
        "tool_permissions": None,
        "note": "No tool list shown in main panel; has a separate 'View details' button"
    },
    "Linear": {
        "connected": True,
        "disconnect_button": True,
        "description": "Manage issues, projects, and team workflows in Linear with natural language. Create and update issues, track progress, plan cycles, and coordinate development tasks using Linear's streamlined project management interface for faster, more efficient workflows.",
        "tool_permissions": {
            "read_only_tools": {
                "count": 21,
                "default_permission": "Custom",
                "tools_visible": [
                    {"name": "extract_images", "permission": "auto-allow"},
                    {"name": "get_attachment", "permission": "auto-allow"},
                    {"name": "get_document", "permission": "auto-allow"},
                    {"name": "get_issue", "permission": "auto-allow"},
                    {"name": "get_issue_status", "permission": "auto-allow"},
                    {"name": "get_milestone", "permission": "auto-allow"},
                    {"name": "get_project", "permission": "auto-allow"},
                    {"name": "get_team", "permission": "auto-allow"}
                ],
                "note": "13 more read-only tools below fold"
            }
        }
    },
    "Sentry": {
        "connected": True,
        "disconnect_button": True,
        "description": "Access Sentry Issue and Error details, create projects and query for project information, trigger Seer Issue Fix run to generate root cause analysis, and retrieve solutions. Access Sentry context to debug applications faster.",
        "tool_permissions": {
            "read_only_tools": {
                "count": 15,
                "default_permission": "Custom",
                "tools_visible": [
                    {"name": "find_dsns", "permission": "auto-allow"},
                    {"name": "find_organizations", "permission": "auto-allow"},
                    {"name": "find_projects", "permission": "auto-allow"},
                    {"name": "find_releases", "permission": "auto-allow"},
                    {"name": "find_teams", "permission": "auto-allow"},
                    {"name": "get_doc", "permission": "auto-allow"},
                    {"name": "get_event_attachment", "permission": "auto-allow"},
                    {"name": "get_issue_details", "permission": "needs-approval"},
                    {"name": "get_issue_tag_values", "permission": "auto-allow"}
                ],
                "note": "6 more read-only tools below fold"
            }
        }
    },
    "Slack": {
        "connected": True,
        "disconnect_button": True,
        "label": "Interactive",
        "description": "Connect to Slack to share messages and create canvases directly to simplify collaboration and boost productivity. Search and retrieve messages, channels, threads, files, and users, giving Claude the context to streamline your work.",
        "tool_permissions": {
            "interactive_tools": {
                "count": 1,
                "default_permission": "Always allow",
                "tools": [
                    {"name": "Create a draft message", "permission": "auto-allow"}
                ]
            },
            "read_only_tools": {
                "count": 8,
                "default_permission": "Always allow",
                "tools": [
                    {"name": "Search public messages and files", "permission": "auto-allow"},
                    {"name": "Search messages and files", "permission": "auto-allow"},
                    {"name": "Search channels", "permission": "auto-allow"},
                    {"name": "Search users", "permission": "auto-allow"},
                    {"name": "Read channel messages", "permission": "auto-allow"},
                    {"name": "Read thread messages", "permission": "auto-allow"},
                    {"name": "Read a canvas", "permission": "auto-allow"},
                    {"name": "Read user profile", "permission": "auto-allow"}
                ]
            },
            "write_delete_tools": {
                "count": 3,
                "default_permission": "Needs approval",
                "tools": [
                    {"name": "Send message", "permission": "needs-approval"},
                    {"name": "Schedule message", "permission": "needs-approval"},
                    {"name": "Create a canvas", "permission": "needs-approval"}
                ]
            }
        }
    },
    "Vercel": {
        "connected": True,
        "disconnect_button": True,
        "description": "Vercel MCP is Vercel's official MCP server, allowing you to search and navigate documentation, manage projects and deployments, and analyze deployment logs—all in one place.",
        "tool_permissions": {
            "read_only_tools": {
                "count": 11,
                "default_permission": "Always allow",
                "tools_visible": [
                    {"name": "check_domain_availability_and_price", "permission": "auto-allow"},
                    {"name": "get_access_to_vercel_url", "permission": "auto-allow"},
                    {"name": "get_deployment", "permission": "auto-allow"},
                    {"name": "get_deployment_build_logs", "permission": "auto-allow"},
                    {"name": "get_project", "permission": "auto-allow"},
                    {"name": "get_runtime_logs", "permission": "auto-allow"},
                    {"name": "list_deployments", "permission": "auto-allow"},
                    {"name": "list_projects", "permission": "auto-allow"},
                    {"name": "list_teams", "permission": "auto-allow"}
                ],
                "note": "2 more read-only tools below fold"
            }
        }
    }
}

skill_details = {
    "algorithmic_art": {
        "name": "algorithmic-art",
        "enabled": False,
        "added_by": "Anthropic",
        "description": "Creating algorithmic art using p5.js with seeded randomness and interactive parameter exploration. Use this when users request creating art using code, generative art, algorithmic art, flow fields, or particle systems. Create original algorithmic art rather than copying existing artists' work to avoid copyright violations.",
        "files": ["SKILL.md", "templates/", "LICENSE.txt"],
        "skill_content_summary": {
            "two_step_process": ["1. Algorithmic Philosophy Creation (.md file)", "2. Express by creating p5.js generative art (.html + .js files)"],
            "philosophy_creation": "Create an ALGORITHMIC PHILOSOPHY (not static images) — a computational aesthetic movement expressed through code",
            "philosophy_themes": ["Computational processes, emergent behavior, mathematical beauty", "Seeded randomness, noise fields, organic systems", "Particles, flows, fields, forces", "Parametric variation and controlled chaos"],
            "philosophy_format": "4-6 paragraphs, named movement (1-2 words), poetic computational philosophy",
            "implementation": {
                "framework": "p5.js (CDN)",
                "canvas_size": "1200x1200",
                "template": "templates/viewer.html (REQUIRED starting point)",
                "template_reference": "templates/generator_template.js",
                "output": "Single self-contained HTML artifact with inline p5.js",
                "branding": "Anthropic branding (Poppins/Lora fonts, light colors, gradient backdrop)"
            },
            "sidebar_structure": {
                "fixed": ["Seed section (display, prev/next, random, jump-to-seed)", "Actions section (Regenerate, Reset, Download PNG)"],
                "variable": ["Parameters section (sliders, inputs per artwork)", "Colors section (optional, depends on artwork)"]
            },
            "technical_requirements": ["Seeded randomness (Art Blocks pattern)", "Parameter structure driven by philosophy", "Real-time parameter updates via UI controls", "Same seed always produces identical output"],
            "craftsmanship": ["Balance: complexity without noise", "Color Harmony: thoughtful palettes", "Composition: visual hierarchy and flow", "Performance: optimized for real-time", "Reproducibility: deterministic seeds"]
        }
    },
    "brand_guidelines": {
        "name": "brand-guidelines",
        "enabled": False,
        "added_by": "Anthropic",
        "description": "Applies Anthropic's official brand colors and typography to any sort of artifact that may benefit from having Anthropic's look-and-feel. Use it when brand colors or style guidelines, visual formatting, or company design standards apply.",
        "files": ["SKILL.md", "LICENSE.txt"],
        "skill_content_summary": {
            "title": "Anthropic Brand Styling",
            "keywords": "branding, corporate identity, visual identity, post-processing, styling, brand colors, typography, Anthropic brand, visual formatting, visual design",
            "sections_visible": ["Overview", "Brand Guidelines"]
        }
    },
    "canvas_design": {
        "name": "canvas-design",
        "enabled": False,
        "added_by": "Anthropic",
        "description": "Create beautiful visual art in .png and .pdf documents using design philosophy. You should use this skill when the user asks to create a poster, piece of art, design, or other static piece. Create original visual designs, never copying existing artists' work to avoid copyright violations.",
        "files": ["SKILL.md", "canvas-fonts/", "LICENSE.txt"],
        "skill_content_summary": {
            "approach": "Design philosophies — aesthetic movements expressed VISUALLY",
            "output_formats": [".md", ".pdf", ".png"]
        }
    },
    "doc_coauthoring": {
        "name": "doc-coauthoring",
        "enabled": False,
        "added_by": "Anthropic",
        "description": "Guide users through a structured workflow for co-authoring documentation. Use when user wants to write documentation, proposals, technical specs, decision docs, or similar structured content. This workflow helps users efficiently transfer context, refine content through iteration, and verify the doc works for readers. Trigger when user mentions writing docs, creating proposals, drafting specs, or similar documentation tasks.",
        "files": ["SKILL.md"],
        "skill_content_summary": {
            "title": "Doc Co-Authoring Workflow",
            "three_stages": ["Context Gathering", "Refinement & Structure", "Reader Testing"],
            "trigger_conditions": "User mentions writing documentation: 'write a doc', 'draft a proposal', 'create a...'"
        }
    },
    "internal_comms": {
        "name": "internal-comms",
        "enabled": False,
        "added_by": "Anthropic",
        "description": "A set of resources to help me write all kinds of internal communications, using the formats that my company likes to use. Claude should use this skill whenever asked to write some sort of internal communications (status reports, leadership updates, 3P updates, company newsletters, FAQs, incident reports, project updates, etc.).",
        "files": ["SKILL.md", "examples/", "LICENSE.txt"],
        "skill_content_summary": {
            "use_cases": ["3P updates (Progress, Plans, Problems)", "Company newsletters", "FAQ responses", "Status reports", "Leadership updates"]
        }
    },
    "slack_gif_creator": {
        "name": "slack-gif-creator",
        "enabled": False,
        "added_by": "Anthropic",
        "description": "Knowledge and utilities for creating animated GIFs optimized for Slack. Provides constraints, validation tools, and animation concepts. Use when users request animated GIFs for Slack like 'make me a GIF of X doing Y for Slack.'",
        "files": ["SKILL.md", "core/", "LICENSE.txt", "requirements.txt"],
        "skill_content_summary": {
            "title": "Slack GIF Creator",
            "slack_requirements": {
                "emoji_gifs": "128x128 (recommended)",
                "message_gifs": "480x480"
            }
        }
    },
    "theme_factory": {
        "name": "theme-factory",
        "enabled": False,
        "added_by": "Anthropic",
        "description": "Toolkit for styling artifacts with a theme. These artifacts can be slides, docs, reportings, HTML landing pages, etc. There are 10 pre-set themes with colors/fonts that you can apply to any artifact that has been creating, or can generate a new theme on-the-fly.",
        "files": ["SKILL.md", "themes/", "LICENSE.txt", "theme-showcase.pdf"],
        "skill_content_summary": {
            "title": "Theme Factory Skill",
            "purpose": "Apply consistent, professional styling to presentation slide decks and other artifacts",
            "preset_themes": 10,
            "can_generate_new_themes": True
        }
    },
    "mcp_builder": {
        "name": "mcp-builder",
        "enabled": True,
        "added_by": "Anthropic",
        "description": "Guide for creating high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services through well-designed tools. Use when building MCP servers to integrate external APIs or services, whether in Python (FastMCP) or Node/TypeScript (MCP SDK).",
        "files": ["SKILL.md", "reference/", "scripts/", "LICENSE.txt"],
        "skill_content_summary": {
            "visible_sections": ["Complete working examples", "Quality checklist", "Evaluation Guide (Load During Phase 4)"],
            "evaluation_guide_includes": ["Question creation guidelines", "Answer verification strategies", "XML format specifications", "Example questions and answers", "Running an evaluation with the provided scripts"]
        }
    },
    "skill_creator": {
        "name": "skill-creator",
        "enabled": True,
        "added_by": "Anthropic",
        "description": "Create new skills, modify and improve existing skills, and measure skill performance. Use when users want to create a skill from scratch, edit, or optimize an existing skill, run evals to test a skill, benchmark skill performance with variance analysis, or optimize a skill's description for better triggering accuracy.",
        "files": ["SKILL.md", "agents/", "assets/", "eval-viewer/", "references/", "scripts/", "LICENSE.txt"],
        "skill_content_summary": {
            "title": "Skill Creator",
            "process": ["Decide what you want the skill to do and roughly how it should do it", "Write a draft of the skill", "Create a few test prompts and run claude-with-access-to-the-skill on them", "Help the user evaluate the results both qualitatively and quantitatively"]
        }
    },
    "web_artifacts_builder": {
        "name": "web-artifacts-builder",
        "enabled": True,
        "added_by": "Anthropic",
        "description": "Suite of tools for creating elaborate, multi-component claude.ai HTML artifacts using modern frontend web technologies (React, Tailwind CSS, shadcn/ui). Use for complex artifacts requiring state management, routing, or shadcn/ui components - not for simple single-file HTML/JSX artifacts.",
        "files": ["SKILL.md", "scripts/", "LICENSE.txt"],
        "skill_content_summary": {
            "output": "bundle.html — a self-contained artifact with all JavaScript, CSS, and dependencies inlined",
            "requirements": "Project must have an index.html in root directory",
            "bundling": ["Installs bundling dependencies (parcel, @parcel/config-default, parcel-resolver-tspaths, html-inline)", "Creates .parcelrc config with path alias support", "Builds with Parcel (no source maps)"]
        }
    }
}

# Page metadata
page_metadata = {
    "org": {
        "display_name": "alex-jadecli",
        "org_id": "jadecli-orgid-22ddd267-e411-4897-8711-65788596b9c6"
    },
    "page": {
        "url": "https://claude.ai/customize",
        "title": "Customize",
        "sections": ["Skills", "Connectors"]
    }
}
