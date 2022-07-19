use aws_lambda_events::encodings::Body;
use aws_lambda_events::event::apigw::{ApiGatewayV2httpRequest, ApiGatewayV2httpResponse};
use http::header::HeaderMap;
use lambda_runtime::{handler_fn, Context, Error};
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


#[tokio::main]
async fn main() -> Result<(), Error> {
    SimpleLogger::new().with_utc_timestamps().init().unwrap();

    let func = handler_fn(func);
    lambda_runtime::run(func).await?;
    Ok(())
}

async fn func(event: ApiGatewayV2httpRequest, _: Context) -> Result<ApiGatewayV2httpResponse, Error> {
    log::debug!("Running in debug mode");
    let method = event.request_context.http.method.as_str();
    let path = event.raw_path.unwrap();

    log::info!("Received {} request on {}", method, path);

    let url = "mysql://admin:mZYV4xQea6epa6JCSDX8@mysql-demo-1.czgfrnfxh2g1.us-east-2.rds.amazonaws.com:3307/storefront";
    let pool = Pool::new(url)?;

    let mut conn = pool.get_conn()?;

    let staff = conn
        .query_map(
            "SELECT staff_id, first_name, last_name, email, username, password FROM staff",
            |(staff_id, first_name, last_name, email, username, password)| {
                Staff { staff_id, first_name, last_name, email, username, password }
            },
        )?;


    let resp = ApiGatewayV2httpResponse {
        status_code: 200,
        headers: HeaderMap::new(),
        multi_value_headers: HeaderMap::new(),
        body: Some(Body::Text(format!("Heres the staff: \n '{:?}'", staff))),
        is_base64_encoded: Some(false),
        cookies: Vec::new(),
    };

    Ok(resp)
}