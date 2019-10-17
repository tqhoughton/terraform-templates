resource "aws_cloudformation_stack" "websocket_api" {
  name = "${var.websocket_api_stack_name}"

  depends_on = [
    "module.websockets_service_onconnect_lambda",
    "module.websockets_service_ondisconnect_lambda",
    "module.websockets_service_authorizer_lambda"
  ]

  template_body = <<EOF
Resources:
  WebSocketApi:
    Type: AWS::ApiGatewayV2::Api
    Properties:
      Name: ${var.websocket_api_stack_name}
      ProtocolType: WEBSOCKET
      RouteSelectionExpression: $request.body.action
  
  WebSocketAuth:
    Type: "AWS::ApiGatewayV2::Authorizer"
    Properties:
      Name: lambda-auth
      ApiId: !Ref WebSocketApi
      AuthorizerType: REQUEST
      AuthorizerUri: arn:aws:apigateway:${var.target_aws_region}:lambda:path/2015-03-31/functions/${module.websockets_service_authorizer_lambda.function_arn}/invocations
      IdentitySource:
        - "route.request.querystring.Authorization"
  
  AuthorizerFunctionPermission:
    Type: AWS::Lambda::Permission
    DependsOn: [ WebSocketApi ]
    Properties:
      Action: lambda:InvokeFunction
      FunctionName: ${module.websockets_service_authorizer_lambda.function_name}
      Principal: apigateway.amazonaws.com
  
  OnConnectRouteIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref WebSocketApi
      IntegrationType: AWS_PROXY
      IntegrationUri: arn:aws:apigateway:${var.target_aws_region}:lambda:path/2015-03-31/functions/${module.websockets_service_onconnect_lambda.function_arn}/invocations

  OnConnectApiRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref WebSocketApi
      RouteKey: $connect
      AuthorizationType: CUSTOM
      AuthorizerId: !Ref WebSocketAuth
      OperationName: connect
      Target: !Join ['/', [ integrations, !Ref OnConnectRouteIntegration ] ]
  
  OnConnectFunctionPermission:
    Type: AWS::Lambda::Permission
    DependsOn: [ WebSocketApi ]
    Properties:
      Action: lambda:invokeFunction
      FunctionName: ${module.websockets_service_onconnect_lambda.function_name}
      Principal: apigateway.amazonaws.com
  
  OnDisconnectRouteIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref WebSocketApi
      IntegrationType: AWS_PROXY
      IntegrationUri: arn:aws:apigateway:${var.target_aws_region}:lambda:path/2015-03-31/functions/${module.websockets_service_ondisconnect_lambda.function_arn}/invocations

  OnDisconnectApiRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref WebSocketApi
      RouteKey: $disconnect
      AuthorizationType: NONE
      OperationName: disconnect
      Target: !Join ['/', [ integrations, !Ref OnDisconnectRouteIntegration ] ]

  OnDisconnectFunctionPermission:
    Type: AWS::Lambda::Permission
    DependsOn: [ WebSocketApi ]
    Properties:
      Action: lambda:invokeFunction
      FunctionName: ${module.websockets_service_ondisconnect_lambda.function_name}
      Principal: apigateway.amazonaws.com
  
  DefaultRouteIntegration:
    Type: AWS::ApiGatewayV2::Integration
    Properties:
      ApiId: !Ref WebSocketApi
      IntegrationType: AWS_PROXY
      IntegrationUri: arn:aws:apigateway:${var.target_aws_region}:lambda:path/2015-03-31/functions/${module.websockets_service_default_lambda.function_arn}/invocations

  DefaultApiRoute:
    Type: AWS::ApiGatewayV2::Route
    Properties:
      ApiId: !Ref WebSocketApi
      RouteKey: $default
      AuthorizationType: NONE
      OperationName: default
      Target: !Join ['/', [ integrations, !Ref DefaultRouteIntegration ] ]

  DefaultFunctionPermission:
    Type: AWS::Lambda::Permission
    DependsOn: [ WebSocketApi ]
    Properties:
      Action: lambda:invokeFunction
      FunctionName: ${module.websockets_service_default_lambda.function_name}
      Principal: apigateway.amazonaws.com
Outputs:
  WebSocketApi:
    Value: !Ref WebSocketApi
EOF
}

resource "null_resource" "create_stage" {
  depends_on = [
    "aws_cloudformation_stack.websocket_api"
  ]

  triggers {
    # DO NOT CHANGE THIS
    invocation = "2019-08-26:T10:00:00Z"
  }

  provisioner "local-exec" {
    command = "aws apigatewayv2 create-stage --api-id ${aws_cloudformation_stack.websocket_api.outputs["WebSocketApi"]} --stage-name ${var.websocket_api_stage}"
  }
}

resource "null_resource" "create_deployment" {
  depends_on = [
    "null_resource.create_stage"
  ]

  triggers {
    lambda = "${md5(file("./terraform/apigateway_v2.tf"))}"
  }

  provisioner "local-exec" {
    command = "aws apigatewayv2 create-deployment --api-id ${aws_cloudformation_stack.websocket_api.outputs["WebSocketApi"]} --stage-name ${var.websocket_api_stage} --description 'Deployed by terraform'"
  }
}
