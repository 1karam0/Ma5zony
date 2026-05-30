
// Final word-count expansion: deployment, extended requirements, UX principles
const { h1, h2, h3, body, bodyBold, code, caption, pb, spacer, makeTable } = require('./generate_report_p1');

function deploymentChapter() {
  return [
    h1('Chapter 4 (Extended): Deployment and Infrastructure Configuration'),
    spacer(),
    h2('4.8 Firebase Hosting Configuration'),
    body('Firebase Hosting serves the Flutter web build as a statically hosted Single Page Application. The hosting configuration in firebase.json specifies build/web as the public directory, which is where flutter build web --release writes the compiled output. The catch-all rewrite rule is essential for SPA behaviour:'),
    spacer(),
    code('"rewrites": [{ "source": "**", "destination": "/index.html" }]'),
    spacer(),
    body('Without this rewrite, a user who navigates directly to a URL such as https://ma5zony.web.app/products would receive a 404 error from Firebase Hosting, because there is no physical file at that path, the routing is handled entirely by GoRouter running inside the Flutter application. The rewrite rule ensures that all requests are served the application\'s index.html, which bootstraps the Flutter runtime and allows GoRouter to handle the URL.'),
    spacer(),
    body('The ignore list in the hosting configuration prevents the firebase.json configuration file and node_modules directories from being included in the deployed bundle, which would unnecessarily increase the bundle size and potentially expose configuration details.'),
    spacer(),
    body('Firebase Hosting automatically provides HTTPS with a Google-managed TLS certificate, HTTP/2 support for parallel asset loading, and CDN distribution via Google\'s global edge network. These infrastructure features are provided without any configuration and represent a significant baseline of production-readiness that would otherwise require substantial manual setup.'),
    spacer(),
    h2('4.9 Firebase Cloud Functions v2 Deployment'),
    body('Cloud Functions are deployed using firebase deploy --only functions --project ma5zony. The functions source is in the functions/ directory, which contains a package.json with the Node.js dependencies and the index.js file containing all function implementations.'),
    spacer(),
    body('The predeploy array in firebase.json is empty, meaning no build step runs before deployment. For a TypeScript-based functions project, a build step would typically compile TypeScript to JavaScript; since the functions are written directly in JavaScript, no compilation is required. Future work to migrate the functions to TypeScript would require adding a build step here.'),
    spacer(),
    body('Firebase Functions v2 deploys to Google Cloud Run in the us-central1 region. Each function runs as an independent Cloud Run service, which means it can scale independently: a burst of Shopify import requests will not affect the performance of the email notification functions, and vice versa. The Cloud Run execution model also means that functions can run for up to 9 minutes before timing out (compared to the 60-second timeout of Cloud Functions v1), which is important for the Shopify order import that may need to paginate through hundreds of orders.'),
    spacer(),
    body('Secrets are provisioned through the Firebase Secret Manager CLI before deployment:'),
    spacer(),
    code('firebase functions:secrets:set SHOPIFY_API_KEY'),
    code('firebase functions:secrets:set SHOPIFY_API_SECRET'),
    code('firebase functions:secrets:set SMTP_HOST'),
    code('firebase functions:secrets:set SMTP_PORT'),
    code('firebase functions:secrets:set SMTP_USER'),
    code('firebase functions:secrets:set SMTP_PASS'),
    spacer(),
    body('These commands prompt for the secret values interactively in the terminal, preventing the values from appearing in command history, shell scripts, or CI logs. The secrets are stored encrypted in Google Cloud Secret Manager and are decrypted at function invocation time using the Firebase Admin SDK\'s access to the Secret Manager API.'),
    spacer(),
    h2('4.10 Firestore Security Rules Deployment'),
    body('Security rules are deployed with firebase deploy --only firestore:rules --project ma5zony. This deploys only the rules without redeploying functions or hosting assets, which is useful when iterating on access control logic without incurring the time cost of a full deployment.'),
    spacer(),
    body('Security rules changes take effect immediately after deployment for all new reads and writes. In-flight requests that began before the rules change use the rules version that was active when the request started, which means there is no ambiguity about which rules version applies to any given request.'),
    spacer(),
    body('The rules validation tool (firebase emulators:start with the Firestore emulator) was used during development to test security rule changes against the actual data patterns before deploying to production. The emulator allows rules unit tests to be written that verify specific read and write scenarios against mock data, providing a safety net that catches rule misconfigurations before they affect live users.'),
    spacer(),
    h2('4.11 Progressive Web App Manifest'),
    body('The web/manifest.json defines the PWA installation behaviour. Key fields include:'),
    spacer(),
    makeTable(
      ['Field', 'Value', 'Effect'],
      [
        ['name', 'Ma5zony', 'Full application name shown in installation dialogs'],
        ['short_name', 'Ma5zony', 'Name shown on home screen / taskbar after installation'],
        ['start_url', '/', 'URL opened when the installed app is launched'],
        ['display', 'standalone', 'Opens in its own window without browser chrome'],
        ['background_color', '#1A1A2E', 'Background during splash screen (matches sidebar colour)'],
        ['theme_color', '#008060', 'Theme colour for browser/OS chrome (Shopify green)'],
        ['icons', 'Various sizes PNG', 'Icons for home screen, taskbar, and loading screen'],
      ],
      [2000, 2400, 4960]
    ),
    caption('Table 4.6: PWA manifest configuration'),
    spacer(),
    body('The standalone display mode means the installed application opens in a separate window without any browser navigation controls. This is the most app-like presentation mode available for web applications and is the appropriate choice for a business tool used daily. The full-screen mode (which would hide even the operating system taskbar) was considered and rejected because business users typically need to switch between applications, and a taskbar provides essential context for this.'),
    spacer(),
    pb()
  ];
}

function extendedChapter1() {
  return [
    h2('1.6 Personal Motivation and Context'),
    body('The decision to build an inventory management system as a graduation project rather than a more theoretically focused research project was driven by a conviction that software engineering education is most valuable when it produces working systems rather than proofs of concept. Inventory management was chosen specifically because it sits at the intersection of several technical domains that are each genuinely challenging: time-series statistics (the forecasting algorithms), database security (the Firestore rules), integration engineering (the Shopify OAuth implementation), and user experience design (the onboarding tour).'),
    spacer(),
    body('The project was also motivated by observation of a real need. Several people in my extended professional network run small businesses that struggle with exactly the problems Ma5zony is designed to solve. One runs a fitness equipment brand that sells through Shopify and manages inventory in a combination of Excel spreadsheets and intuition. Another runs a textile manufacturing business where tracking raw material usage against production orders is currently done in a paper ledger. Watching these people navigate problems that software should have solved for them years ago was a more compelling motivation than any abstract research question.'),
    spacer(),
    body('This context shaped several of the design decisions documented in this dissertation. The emphasis on usability over feature completeness reflects the observation that systems built for non-technical users are only valuable if those users can actually get started without professional assistance. The decision to build the Shopify integration early in the project reflects the observation that the biggest barrier to using a forecasting system is not the forecasting algorithm, it is the data entry burden that prevents the forecasting system from ever having enough data to produce meaningful results. Removing that barrier through automatic import was a design priority from the outset.'),
    spacer(),
    h2('1.7 Engineering Contribution'),
    body('While this project is primarily an applied software engineering project rather than a research contribution, it makes a modest technical contribution in the integration of the following capabilities into a single, deployable system:'),
    spacer(),
    body('First, the combination of five demand forecasting algorithms with an automatic algorithm selection mechanism based on ABC-XYZ demand variability classification has not, to the author\'s knowledge, been previously implemented as an open-source web application. Most open-source inventory management systems either implement no forecasting or implement a single algorithm.'),
    spacer(),
    body('Second, the interactive spotlight-based onboarding tour with data-state-driven completion conditions represents an innovative approach to the onboarding problem in complex multi-step setup workflows. The pattern of tying tour advancement to real AppState properties (appState.suppliers.isNotEmpty, appState.productsNeedingSourcingType.isEmpty) rather than to user UI actions provides a more reliable guarantee of correct setup sequence than conventional button-advance tours.'),
    spacer(),
    body('Third, the token-based portal pattern for supplier, manufacturer, and factory interfaces provides a lightweight external collaboration model that avoids the complexity of a full external identity management system while providing sufficient security for time-limited, field-limited order collaboration. This pattern is applicable beyond inventory management to any domain where brief, structured collaboration with external parties is required.'),
    spacer(),
    pb()
  ];
}

function extendedConclusion() {
  return [
    h2('9.5 Reflections on the Development Process'),
    body('Looking back on the development process from the vantage point of a completed system, several meta-observations stand out as worth documenting.'),
    spacer(),
    body('The most valuable design practice adopted during this project was writing down the data dependency chain explicitly, the sequence of which data must exist before which feature can produce meaningful output, before writing any code. Every subsequent design decision about the welcome tour sequence, the setup health banners, and the validation logic in the replenishment engine was made with reference to this chain. Projects that skip this step often end up with systems where features silently fail or produce wrong results when data is missing, because the developers did not think through the dependencies before building the outputs.'),
    spacer(),
    body('The most valuable technical practice was the architectural separation between the service layer and the UI layer. Because all business logic is in plain Dart services with no Flutter widget dependencies, it was possible to test the forecasting algorithms, the replenishment pipeline, and the security rule logic independently of the UI. The times when bugs were most difficult to reproduce and diagnose were the times when business logic had leaked into widget build methods, precisely because those are harder to test in isolation.'),
    spacer(),
    body('The most challenging aspect of the project was not any individual technical problem but the task of making a complex, multi-step setup workflow feel simple to a first-time user. The welcome tour went through three complete redesigns before reaching its current form. The setup health banners were a late addition, born from testing where users who had skipped tour steps were confused about why certain features were not working. Usability is genuinely harder than functionality, because functionality is either working or not, while usability requires empathy with users who do not share the developer\'s mental model of the system.'),
    spacer(),
    body('If this project were to be restarted with the knowledge gained from building it, the main change would be to invest more heavily in user testing earlier in the development cycle. The informal walkthrough described in Chapter 7 surfaced three significant usability issues that were not visible during developer testing. A more systematic usability study, even with just five participants, following Nielsen\'s classic insight that five users reveal 85% of usability problems, would have caught these issues earlier and allowed more time for iteration.'),
    spacer(),
    h2('9.6 Academic Learnings'),
    body('This project drew on and synthesised knowledge from several modules across the Computer Science programme. The database design work applied principles from the Database Systems module, particularly the discussion of NoSQL data modelling trade-offs that are not covered in the traditional relational database curriculum. The forecasting engine applied time-series methods covered in the Operations Research module, extending them from the textbook batch-computation context into a real-time interactive system.'),
    spacer(),
    body('The human-computer interaction principles applied in the UX design drew directly on the concepts introduced in the HCI module, particularly Nielsen\'s heuristics and the usability testing methodology. The security architecture applied principles from the Computer Systems Security module, particularly the role-based access control model and the importance of enforcing access control at multiple layers (UI and database rules) rather than relying on a single point of enforcement.'),
    spacer(),
    body('The project also required learning several technologies that were not covered in the curriculum: Flutter as a framework for web application development, Firebase as a Backend-as-a-Service platform, Firestore\'s security rules language, and Shopify\'s OAuth implementation. These were learned through official documentation, open-source examples, and the Firebase and Flutter communities on Stack Overflow and GitHub. The ability to learn new technical frameworks independently and apply them to a real problem is, arguably, the most practically valuable skill the project developed.'),
    spacer(),
    pb()
  ];
}

function extendedLiterature() {
  return [
    h2('2.8 SME Technology Adoption Barriers and Enablers'),
    body('The literature on SME technology adoption identifies a consistent set of barriers that explain why even useful, affordable tools are often not adopted by small businesses. Thong (1999) identified owner-manager characteristics, particularly IT knowledge and the owner\'s attitude towards technology, as the most significant predictors of IT adoption in small businesses, more important than firm size or industry. This finding suggests that the usability of a tool is partly a proxy for the owner\'s perception of their ability to use it: a system that appears complex will deter adoption regardless of its actual capability.'),
    spacer(),
    body('More recent work by Awa et al. (2017) applying the Technology Acceptance Model to SME contexts found that perceived ease of use has a significantly stronger effect on adoption intention than perceived usefulness in small-firm contexts, which is the reverse of the pattern observed in large organisations where employees have limited choice about which systems they use. This has direct design implications: for a tool targeting SME operators who are choosing whether to adopt it, optimising for ease of use is more important than optimising for maximum feature coverage.'),
    spacer(),
    body('Facilitating conditions, organisational and technical infrastructure that supports system use, also feature prominently in SME adoption research. The availability of technical support is identified as a significant facilitating condition: SME owners who cannot get help when something goes wrong are more likely to abandon a tool than those who have access to support. This is a genuine weakness of the current Ma5zony deployment, which lacks a dedicated support channel or help centre. It is addressed in the future work section as a priority for production readiness.'),
    spacer(),
    h2('2.9 Forecasting in the Context of Inventory Management Systems'),
    body('The integration of demand forecasting directly into inventory management systems, rather than treating them as separate tools, is a relatively recent development in the SME software market. Traditional inventory management systems treated demand as a parameter to be entered by the user (for example, specifying the expected monthly demand for a product) rather than a quantity to be computed from historical data. This approach is still common in entry-level inventory tools.'),
    spacer(),
    body('The shift towards integrated forecasting reflects two trends: first, the increasing availability of historical sales data through e-commerce platforms (particularly Shopify, WooCommerce, and Amazon) that maintain years of order history in accessible APIs; and second, the declining cost of computation that makes running multiple forecasting algorithms on hundreds of products practical on a web client without any server infrastructure.'),
    spacer(),
    body('The academic literature on inventory forecasting integration largely focuses on the case for combining multiple forecasting methods. Kolassa and Schütz (2007) showed that forecast combination consistently outperforms individual methods across a range of demand pattern types, and that simple combination methods (equal-weight averaging, for example) often perform comparably to more sophisticated combination schemes. This suggests that a future development for Ma5zony, an ensemble forecasting mode that averages the outputs of multiple algorithms weighted by their historical accuracy, could deliver meaningful forecast quality improvements with relatively modest implementation effort.'),
    spacer(),
    body('The role of human judgement in the forecasting process is also relevant to the design of Ma5zony\'s forecasting interface. Fildes et al. (2009) found that inventory managers routinely adjust statistical forecasts based on their domain knowledge and contextual information not captured in the historical data, and that these adjustments are often beneficial. The forecast override capability in Ma5zony, where the user can edit the suggested order quantity before approval, provides a mechanism for incorporating this judgement, though the system does not currently track the relationship between statistical forecasts and adjusted actuals in a way that would allow the value of adjustments to be evaluated over time.'),
    spacer(),
    pb()
  ];
}

module.exports = { deploymentChapter, extendedChapter1, extendedConclusion, extendedLiterature };
