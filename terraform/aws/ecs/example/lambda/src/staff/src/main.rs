use lambda_http::{run, service_fn, Error, IntoResponse, Request, RequestExt, Response};
use lambda_http::request::RequestContext;
use simple_logger::SimpleLogger;
use mysql::Pool;
use mysql::prelude::*;

#[derive(Debug, PartialEq, Eq)]
struct Staff {
    staff_id: i32,
    first_name: Option<String>,
    last_name: Option<String>,
    email: Option<String>,
    username: Option<String>,
    password: Option<String>,
}


/// This is the main body for the function.
/// Write your code inside it.
/// There are some code example in the following URLs:
/// - https://github.com/awslabs/aws-lambda-rust-runtime/tree/main/lambda-http/examples
async fn function_handler(event: Request) -> Result<impl IntoResponse, Error> {
    // Extract some useful information from the request
    log::debug!("Running in debug mode");

    let path = event.raw_http_path();

    let ctx = event.request_context();
    if let RequestContext::ApiGatewayV2(context) = ctx {
        let method = context.http.method.as_str();
        log::info!("Received {} request on {}", method, path);
    } else {
        log::info!("Received UNKNOWN request on {}", path);
    }

    let url = "mysql://admin:mZYV4xQea6epa6JCSDX8@mysql-demo-1.czgfrnfxh2g1.us-east-2.rds.amazonaws.com:3306/storefront";
    let pool = Pool::new(url)?;

    let mut conn = pool.get_conn()?;

    log::info!("Query STAFF");
    let staff = conn
        .query_map(
            "SELECT staff_id, first_name, last_name, email, username, password FROM staff",
            |(staff_id, first_name, last_name, email, username, password)| {
                Staff { staff_id, first_name, last_name, email, username, password }
            },
        )?;

    log::info!("{}", format!("Found STAFF \n {:#?}", staff));

    // Return something that implements IntoResponse.
    // It will be serialized to the right response event automatically by the runtime
    let resp = Response::builder()
        .status(200)
        .header("content-type", "text/html")
        .body(format!("Hello AWS Lambda HTTP request staff on {}", path))
        .map_err(Box::new)?;

    Ok(resp)
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    SimpleLogger::new().with_utc_timestamps().init().unwrap();
    
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        // disabling time is handy because CloudWatch will add the ingestion time.
        .without_time()
        .init();

    run(service_fn(function_handler)).await
}
