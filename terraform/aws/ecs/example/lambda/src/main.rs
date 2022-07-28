use lambda_http::{run, service_fn, Error, IntoResponse, Request, RequestExt, Response};
use lambda_http::request::RequestContext;

fn render_output_css() -> Result<Response<String>, Error> {
    let body = include_str!("../templates/output.css");

    // let body = handlebars.render(&file_path, HashMap::new()).unwrap();
    let resp = Response::builder()
        .status(200)
        .header("content-type", "text/css")
        .body(body.to_string())
        .map_err(Box::new)?;

    Ok(resp)
}

async fn router(
    method: &str,
    path: &str,
) -> Result<impl IntoResponse, Error> {
    let method_path = (method, path);
    match method_path {
        ("GET", "/output.css") => render_output_css(),

        _ => panic!("Failed to match method and path"),
    }
}

async fn function_handler(event: Request) -> Result<impl IntoResponse, Error> {
    let path = event.raw_http_path();

    let ctx = event.request_context();
    let method = match ctx {
        RequestContext::ApiGatewayV2(context) => context.http.method.to_string(),
        _ => "UNKNOWN".to_string(),
    };

    router(&method, &path).await
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        // disabling time is handy because CloudWatch will add the ingestion time.
        .without_time()
        .init();

    run(service_fn(function_handler)).await
}
