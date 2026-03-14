You are a senior front-end engineer and UI designer.
Design and implement a modern, visually appealing, usable single-page website for a company that sells, leases, and finances lawn mowers.

Create a checklist with tasks that need completing in order to accomplish your goal step by step in this agentic workflow, ideally using a checklist. Your task is to use the tools are your disposal to create the site with the following requirements.
Overall requirements
    • Brand / Theme
        ◦ Brand name: GreenLine Mowers
        ◦ Tagline: “Cut smarter. Spend better.”
        ◦ Modern, clean aesthetic.
        ◦ Color direction: greens + neutrals (white, off-white, charcoal), with a bright accent for CTAs.
        ◦ Use plenty of white space, card-style sections, and subtle shadows/rounding.
    • Technical requirements
        ◦ Create multiple files using the tools available to you as needed. Be sure to organize your files like a professional web developer, but don’t go overboard. Brief is good. Styles, scripts, and HTML should be in separate files as you see fit.
            ▪ Semantic HTML
            ▪ Embedded <style> CSS
            ▪ Embedded <script> JS at the bottom
        ◦ No external build tools (no React/Vue/etc.). Plain HTML/CSS/JS only.
        ◦ You may use Google Fonts for typography (include <link> in <head>).
        ◦ No external CSS frameworks (no Tailwind, Bootstrap, etc.).
    • Layout & responsiveness
        ◦ Fully responsive:
            ▪ Desktop: multi-column layout where appropriate.
            ▪ Mobile: stacked layout, readable tap targets, no horizontal scrolling.
        ◦ Sticky or fixed top navigation bar:
            ▪ Logo/brand name on the left
            ▪ Nav links anchored to page sections (e.g., “Products”, “Financing”, “Why Us”, “FAQ”, “Contact”)
            ▪ A prominent “Get a Quote” button on the right (on desktop).
Page sections & content (use mock data)
    1. Hero section
        ◦ Full-width hero or navbar at the top.
        ◦ Large headline (e.g., “Lawn mowers on your terms: buy, lease, or finance.”)
        ◦ Supporting subtext that briefly explains flexibility and savings.
        ◦ Two primary CTAs:
            ▪ “Browse Mowers”
            ▪ “Get Financing Options”
        ◦ A background image treatment or gradient (no actual image needed, can be a placeholder div with gradient). Keep it stylish and keep the theme professiona, modernl and consistent,
        ◦ Small text link or pill-style selector to toggle a short tagline between Buy, Lease, and Finance modes (purely visual, no need for complex logic).
    2. Products section (with Buy / Lease / Finance views)
        ◦ Section title: “Choose your mower.”
        ◦ A toggle or tab control (e.g., three buttons) for:
            ▪ Buy
            ▪ Lease
            ▪ Finance
        ◦ Below the toggle, show a responsive card grid of lawn mowers, filtered based on the active mode.
        ◦ Each product card (use mock data, 6–9 products total):
            ▪ Model name (e.g., “GreenLine Pro 500”)
            ▪ Type (e.g., “Riding mower”, “Push mower”, “Electric”, “Gas”)
            ▪ Key specs (e.g., cutting width, power, battery life)
            ▪ Price info depending on mode:
                • Buy: full price (e.g., “$1,499”)
                • Lease: monthly price + term (e.g., “From $89/mo for 36 months”)
                • Finance: monthly estimate + APR (mock numbers)
            ▪ A small “View details” link or button, plus a primary button like “Add to Plan” or “Get this mower”.
        ◦ Implement the toggle using JavaScript (e.g., add/remove an active class and show/hide relevant pricing text).
    3. Financing / Leasing highlight section
        ◦ A banded section with a different background to visually separate it.
        ◦ Two or three info cards explaining:
            ▪ “Buy” – own it outright, best for long-term use.
            ▪ “Lease” – lower upfront cost, great for seasonal/short-term.
            ▪ “Finance” – split payments over time with transparent terms.
        ◦ Each info card includes:
            ▪ Icon substitute (could be a circle/emoji or CSS shape).
            ▪ Short heading.
            ▪ 2–3 bullet points.
    4. Simple financing estimator
        ◦ A small calculator UI (implemented in JS, doesn’t need to be perfectly accurate, just believable).
        ◦ Inputs (use sliders or selects + number inputs):
            ▪ Select mower price (dropdown with a few example prices)
            ▪ Down payment
            ▪ Term length (in months)
            ▪ APR (use fixed mock APR or let user select)
        ◦ Output:
            ▪ Estimated monthly payment (calculate with a simple loan formula or even a simplified mock formula).
        ◦ Display result in a styled card with emphasis on the monthly payment and a “Request this plan” button (no real backend, just a dummy button).
    5. Comparison table
        ◦ A table that compares Buy vs Lease vs Finance with rows for:
            ▪ Upfront cost
            ▪ Monthly payment
            ▪ Ownership
            ▪ Flexibility
            ▪ Ideal for…
        ◦ Use visual cues (checkmarks, dashes) and clear labeling.
        ◦ Make the table responsive (e.g., horizontally scrollable on mobile).
    6. Testimonials / Social proof
        ◦ Section title: “What our customers say.”
        ◦ 3–4 testimonial cards with mock names, locations, and short quotes.
        ◦ Include star ratings using simple icons (e.g., ★ characters).
    7. FAQ
        ◦ 5–7 frequently asked questions relevant to buying/leasing/financing lawn mowers.
        ◦ Implement a simple accordion interaction:
            ▪ Clicking a question expands/collapses the answer using JavaScript.
            ▪ Only one open at a time OR multiple open, your choice.
    8. Contact / CTA footer
        ◦ Final strong call to action (e.g., “Ready to cut smarter?”).
        ◦ Compact contact form:
            ▪ Name
            ▪ Email
            ▪ Preferred option (dropdown: Buy, Lease, Finance, Not sure)
            ▪ Short message text area
            ▪ “Request a Quote” button (no real submission; just prevent default and show an alert or inline “Submitted!” message).
        ◦ Footer with:
            ▪ Logo or brand name.
            ▪ Basic links (“Privacy”, “Terms”, “Support”).
            ▪ Simple text like “© 2025 GreenLine Mowers. All rights reserved.”
Design & UX details
    • Typography
        ◦ Use 1–2 modern sans-serif fonts from Google Fonts.
        ◦ Clear hierarchy: larger headings, comfortable line-height for body text.
    • Buttons & interactions
        ◦ Clear primary button style (filled) and secondary button style (outlined or subtle).
        ◦ All buttons must do *something*, even if that’s all mock ‘somethings’ now, no button should have no clear effect unless it would submit a form/email, those can be dummy.
        ◦ Subtle hover states for buttons and cards (e.g., slight shadow increase, scale, or background change).
        ◦ Maintain good contrast ratios for accessibility.
    • Accessibility
        ◦ Use semantic HTML5 landmarks (header, nav, main, section, footer).
        ◦ Provide aria attributes where helpful (e.g., accordion controls).
        ◦ Ensure text contrast is readable.
        ◦ All interactive elements should be keyboard-focusable with visible focus outlines.
    • Code style
        ◦ Use clean, readable class names.
        ◦ Keep CSS organized by section with short comments.
        ◦ Keep JavaScript modular where reasonable (e.g., separate functions for tab switching, FAQ accordion, and calculator logic).
        ◦ Organize things by files. Keep files brief. Brevity is ideal!
Output format
    • Important:
        ◦ Produce the HTML files using any tools provided to you.
        ◦ Do not include explanations, prose, or commentary outside the code block.
        ◦ Ensure the code is complete
Runner Script
    • create a little simple as possible bash shell script that will serve this on localhost port 8000 . Only use tools that would come out the box on a fedora 42 server for this simple script. Please only use relative paths for this script as it’s uncertain what environment/directory this will live in.

Extras:
    - please make sure that the 'cards' you can select for mowers have a 'view details' section that creates a popup
    - you do not need to test the website is reachable as you're developing in an isolated/contained environment; instead you can prompt the user that you're done

