using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using MongoDB.Driver;
using MongoDB.Bson;
using KubernetesToDo.Api.Services;

var builder = WebApplication.CreateBuilder(args);

// Configuration - expects Mongo:ConnectionString and Mongo:Database
var configuration = builder.Configuration;
var mongoConn = configuration.GetValue<string>("Mongo:ConnectionString") ?? "mongodb://mongodb:27017";
var mongoDbName = configuration.GetValue<string>("Mongo:Database") ?? "kuber_todo_db";

// Register Mongo client and TodoService
var mongoClient = new MongoClient(mongoConn);
builder.Services.AddSingleton(mongoClient.GetDatabase(mongoDbName));
builder.Services.AddSingleton<TodoService>();

builder.Services.AddControllers();
builder.Services.AddRazorPages();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseRouting();
app.UseAuthorization();

app.UseStaticFiles();

app.MapControllers();
app.MapRazorPages();

// Health endpoint used by Kubernetes readiness/liveness probes
app.MapGet("/health", async (IMongoDatabase db) =>
{
    try
    {
        // Perform a lightweight MongoDB ping to ensure DB connectivity
        var result = await db.RunCommandAsync<BsonDocument>(new BsonDocument("ping", 1));
        // If ping returns ok:1, report healthy
        var okVal = result.Contains("ok") ? result.GetValue("ok").ToDouble() : 0.0;
        if (okVal >= 1.0)
        {
            return Results.Ok(new { status = "OK" });
        }
        return Results.StatusCode(500);
    }
    catch (Exception)
    {
        return Results.StatusCode(500);
    }
});

app.Run();
