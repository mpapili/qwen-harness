# GreenLine Mowers - Single-Page Website

A modern, responsive single-page website for GreenLine Mowers - a company that sells, leases, and finances lawn mowers.

## Features

- **Responsive Design**: Mobile-first approach with breakpoints for tablet and desktop
- **Product Catalog**: 8 lawn mower products with detailed specifications
- **Payment Method Toggle**: Switch between Buy/Lease/Finance views
- **Financing Calculator**: Interactive payment estimator with loan calculations
- **Comparison Table**: Side-by-side comparison of payment options
- **FAQ Section**: Accordion-style frequently asked questions
- **Contact Form**: Validated contact form with success feedback
- **Accessibility**: ARIA labels, keyboard navigation, focus indicators, and reduced motion support

## File Structure

```
/workspace/
├── index.html          # Main HTML file with all sections
├── styles.css          # Complete CSS styling with custom properties
├── app.js              # JavaScript functionality and mock data
├── serve.sh            # HTTP server script (port 8000)
└── README.md           # This documentation file
```

## Quick Start

### Option 1: Using the serve.sh script

```bash
# Make the script executable (if not already done)
chmod +x serve.sh

# Run the server
./serve.sh
```

### Option 2: Manual Python server

```bash
# Using Python 3
python3 -m http.server 8000

# Or using Python 2
python -m SimpleHTTPServer 8000
```

### Option 3: Other HTTP servers

```bash
# Using Node.js (http-server)
npx http-server -p 8000

# Using PHP
php -S localhost:8000
```

## Access the Website

Once the server is running, open your browser and navigate to:

```
http://localhost:8000
```

## Testing Checklist

### Visual Testing

- [ ] All sections render correctly on desktop (1440px)
- [ ] Mobile responsive layout works on 375px
- [ ] Navigation is sticky and scrolls to sections
- [ ] Hero section displays with proper tagline
- [ ] Product cards show correct pricing based on filter

### Functional Testing

- [ ] Product tabs switch and filter correctly (All/Buy/Lease/Finance)
- [ ] "View Details" modal opens and closes
- [ ] Modal can be closed with Escape key
- [ ] Financing calculator produces believable results
- [ ] FAQ accordion expands/collapses
- [ ] Contact form validates input and shows success message

### Accessibility Testing

- [ ] All buttons have hover states
- [ ] Keyboard navigation works (tab order, focus outlines)
- [ ] ARIA labels present on interactive elements
- [ ] Color contrast meets WCAG standards
- [ ] Reduced motion respected

### Browser Compatibility

Test in:
- [ ] Chrome (latest)
- [ ] Firefox (latest)
- [ ] Safari (latest)
- [ ] Edge (latest)

## Product Data

The website includes 8 lawn mower products:

| Model | Type | Buy Price | Lease | Finance |
|-------|------|-----------|-------|---------|
| GreenLine Pro 500 | Riding Mower | $2,499 | $79/mo (36mo) | $69/mo @ 5.9% APR |
| EcoCut Elite | Electric | $1,899 | $59/mo (24mo) | $49/mo @ 4.9% APR |
| PowerMax 65 | Riding Mower | $3,499 | $99/mo (48mo) | $89/mo @ 6.9% APR |
| Compact Pro | Push Mower | $599 | $29/mo (12mo) | $24/mo @ 7.9% APR |
| SilentCut 30 | Electric | $1,299 | $45/mo (24mo) | $39/mo @ 5.5% APR |
| Heavy Duty 72 | Zero-Turn | $5,999 | $149/mo (60mo) | $139/mo @ 7.5% APR |
| Garden Master | Riding Mower | $2,199 | $69/mo (36mo) | $59/mo @ 6.5% APR |
| EcoLite 24 | Push Mower | $799 | $35/mo (18mo) | $29/mo @ 6.0% APR |

## Color Scheme

- **Primary Green**: #2D8659
- **Primary Light**: #4CAF50
- **Accent Orange**: #FF6B35
- **Background**: #F5F5F0
- **Text**: #333333

## Technologies Used

- HTML5 (semantic elements)
- CSS3 (custom properties, grid, flexbox, media queries)
- JavaScript (ES6+, no external dependencies)
- Google Fonts (Inter)

## Customization

### Adding New Products

Edit the `products` array in `app.js`:

```javascript
{
    id: 9,
    model: 'Your New Model',
    type: 'Product Type',
    specs: {
        cuttingWidth: 'XX"',
        powerSource: 'Type',
        // additional specs...
    },
    prices: {
        buy: 0000,
        leaseMonthly: 00,
        leaseTerm: 00,
        financeMonthly: 00,
        financeAPR: 0.0,
        financeTerm: 00
    },
    available: { buy: true, lease: true, finance: true },
    description: 'Product description...'
}
```

### Modifying Colors

Edit the CSS custom properties in `styles.css`:

```css
:root {
    --color-primary: #2D8659;
    --color-accent: #FF6B35;
    /* ... */
}
```

## Known Limitations

- Server is for development/testing only (not production-ready)
- Payment calculator uses simplified loan formula
- Form submission is simulated (no backend)
- Images are CSS-based placeholders

## License

This project is provided as-is for educational and demonstration purposes.

## Support

For issues or questions, please refer to the action item documentation or contact the project maintainer.
